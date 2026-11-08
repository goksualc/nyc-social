import SwiftUI
import MapKit
import CoreLocation

/// Drives one shared walk. The *server* owns the session state; this model opens it, shows it, sends the person's
/// button presses (ready / sharing / finish) and, while the walk is live, exchanges real GPS positions with the partner.
@MainActor @Observable
final class LiveWalkViewModel {
    enum Follow: Equatable { case me, both, route, free }

    let store: AppStore
    let activityID: ID
    let tracker = WalkLocationTracker()
    private let location: LocationService

    private(set) var session: WalkSession?
    private(set) var route: RoutePreview?
    private(set) var partnerPosition: LivePosition?
    private(set) var partnerSeenAt: Date?
    private(set) var isBusy = false
    private(set) var connectionLost = false
    private(set) var loadFailed: String?
    var errorMessage: String?
    var follow: Follow = .me
    var camera: MapCameraPosition = .automatic
    var isMinimized = false
    /// Set once so the completion summary can offer the memory-privacy choices.
    private(set) var finishedWalk: CompletedWalk?
    private(set) var myTrack = MarkerTrack()
    private(set) var partnerTrack = MarkerTrack()
    /// Drives the animation timeline; true only while a marker is gliding.
    private(set) var markersAnimating = false

    private var tasks: [Task<Void, Never>] = []
    private var liveConnected = false
    private var lastPublished: (at: Date, location: CLLocation)?
    private var previousPartner: LivePosition?
    private var started = false

    init(store: AppStore, activityID: ID, location: LocationService) {
        self.store = store
        self.activityID = activityID
        self.location = location
    }

    // MARK: Derived

    var activity: Activity? { store.activity(activityID) }
    var me: User { store.me }
    var myParticipant: WalkSessionParticipant? { session?.participant(me.id) }
    var partnerParticipant: WalkSessionParticipant? { session?.partner(of: me.id) }
    var partner: User? {
        guard let p = partnerParticipant else { return nil }
        return store.user(p.userId) ?? User(id: p.userId, firstName: p.displayName, bio: "", hobbies: [], avatarPath: p.avatarPath)
    }
    var iAmSharing: Bool { myParticipant?.isSharing ?? false }
    var status: WalkSessionStatus? { session?.status }
    var isLowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled || (UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel < 0.15 && UIDevice.current.batteryState != .charging) }
    var locationDenied: Bool { location.isDenied || tracker.permissionRevoked }

    /// "Location temporarily unavailable" when the partner has not sent a usable position recently (or ever).
    func partnerIsStale(now: Date) -> Bool {
        guard let seen = partnerSeenAt else { return true }
        return now.timeIntervalSince(seen) > 45
    }

    var destinationName: String { activity?.walk.to.publicLabel ?? "your destination" }

    /// Metres left along the route from my latest fix (straight-line ×1.3 when there is no route yet).
    var remainingMeters: Double? {
        guard let activity, let here = tracker.latest else { return route?.distance }
        let dest = activity.walk.to.coordinate
        guard let route, route.coordinates.count >= 2 else { return Coordinate(here.coordinate).distance(to: dest) * 1.3 }
        let k = nearestIndex(to: Coordinate(here.coordinate), in: route.coordinates)
        var left = Coordinate(here.coordinate).distance(to: route.coordinates[k])
        for i in k..<(route.coordinates.count - 1) { left += route.coordinates[i].distance(to: route.coordinates[i + 1]) }
        return left
    }

    var progress: Double {
        guard let total = route?.distance, total > 0, let left = remainingMeters else { return 0 }
        return min(max(1 - left / total, 0), 1)
    }

    var etaDate: Date? { remainingMeters.map { Date().addingTimeInterval($0 / 1.35) } }

    /// MapKit's next instruction, only when MapKit produced the route.
    var nextInstruction: String? {
        guard let route, !route.isEstimate, !route.steps.isEmpty, let here = tracker.latest else { return nil }
        let k = nearestIndex(to: Coordinate(here.coordinate), in: route.coordinates)
        return route.steps.first { $0.startIndex > k }?.instruction
    }

    private func nearestIndex(to c: Coordinate, in coords: [Coordinate]) -> Int {
        coords.indices.min { coords[$0].distance(to: c) < coords[$1].distance(to: c) } ?? 0
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        await openSession()
        if LaunchOptions.current.readyAll { await imReady() }   // debug: jump straight into the live map
        if let activity {
            route = await RouteService.walkingRoute(from: activity.walk.from.coordinate, to: activity.walk.to.coordinate)
            frameRoute()
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self?.refresh()
            }
        })
    }

    /// Called when the screen goes away. Stops tracking only if the walk is not live; a live walk keeps going in the background.
    func stop(endTracking: Bool) async {
        tasks.forEach { $0.cancel() }
        tasks = []
        if endTracking { tracker.stop(); await disconnectLive() }
        started = false
    }

    private func openSession() async {
        do {
            session = try await store.walks.openSession(activityID: activityID)
            loadFailed = nil
            await syncLive()
        } catch {
            loadFailed = ErrorPresenter.message(for: error, fallback: "Couldn't open this walk. Try again.")
        }
    }

    func refresh() async {
        if session == nil { await openSession(); return }
        do {
            if let next = try await store.walks.session(activityID: activityID) { session = next }
            await syncLive()
        } catch { if ErrorPresenter.isSessionExpired(error) { store.onSessionExpired?() } }
    }

    // MARK: Button presses (each is one server call; the server decides what happens)

    func imReady() async {
        guard let id = session?.id, !isBusy else { return }
        if location.canAskForPermission { location.requestWhenInUse() }
        await location.requestTemporaryPrecise()
        await perform { self.session = try await self.store.walks.setReady(sessionID: id) }
        await syncLive()
    }

    func setSharing(_ enabled: Bool) async {
        guard let id = session?.id, !isBusy else { return }
        await perform { self.session = try await self.store.walks.setSharing(sessionID: id, enabled: enabled) }
        await syncLive()
    }

    /// "Yes, finish my walk" — or, for the second person, "Yes, we finished".
    func finish() async {
        guard let id = session?.id, !isBusy else { return }
        let walked = Int(tracker.distanceMeters)
        await perform { self.session = try await self.store.walks.finish(sessionID: id, distanceMeters: walked) }
        tracker.stop()
        await disconnectLive()
        await loadFinishedWalk()
    }

    func endEarly() async {
        guard let id = session?.id, !isBusy else { return }
        await perform { self.session = try await self.store.walks.endEarly(sessionID: id) }
        tracker.stop()
        await disconnectLive()
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch {
            errorMessage = ErrorPresenter.message(for: error, fallback: "That didn't work. Try again.")
        }
    }

    func loadFinishedWalk() async {
        guard session?.status == .completed, let id = session?.id else { return }
        finishedWalk = try? await store.walks.history().first { $0.id == id }
    }

    func setMemoryPrefs(showOnProfile: Bool? = nil, revealPartner: Bool? = nil) async {
        guard let id = session?.id else { return }
        try? await store.walks.setMemoryPrefs(sessionID: id, showOnProfile: showOnProfile, revealPartner: revealPartner)
        await loadFinishedWalk()
    }

    // MARK: Live tracking

    /// Brings tracking and the channel in line with what the server says: live + I'm sharing → track and exchange positions.
    private func syncLive() async {
        guard let session else { return }
        if session.status == .completed { await loadFinishedWalk() }
        if session.status.isLive {
            if !tracker.isTracking, !location.isDenied { tracker.onFix = { [weak self] in self?.didFix($0) }; tracker.start() }
            if iAmSharing && !liveConnected { await connectLive(session) }
            if !iAmSharing && liveConnected { await disconnectLive() }
        } else {
            if tracker.isTracking { tracker.stop() }
            if liveConnected { await disconnectLive() }
        }
    }

    private func connectLive(_ session: WalkSession) async {
        guard let live = store.live else { return }
        do {
            let streams = try await live.connect(sessionID: session.id, myID: me.id)
            liveConnected = true
            connectionLost = false
            tasks.append(Task { [weak self] in
                for await position in streams.positions { self?.receive(position) }
            })
            tasks.append(Task { [weak self] in
                for await _ in streams.sessionChanged { await self?.refresh() }
            })
            tasks.append(Task { [weak self] in
                for await _ in streams.connectionLost {
                    self?.liveConnected = false
                    self?.connectionLost = true
                }
            })
        } catch {
            // Refused by the server (not sharing / not live) or offline: show it, retry on the next refresh.
            liveConnected = false
            connectionLost = true
        }
    }

    private func disconnectLive() async {
        await store.live?.disconnect()
        liveConnected = false
        partnerPosition = nil
        previousPartner = nil
    }

    /// Sends a position when I've moved meaningfully or a few seconds have passed. Fewer sends in Low Power Mode.
    private func didFix(_ fix: CLLocation) {
        myTrack.move(to: fix.coordinate)
        pulseMarkers()
        if let last = lastPublished {
            let dt = fix.timestamp.timeIntervalSince(last.at)
            let moved = fix.distance(from: last.location)
            let minInterval: TimeInterval = isLowPower ? 15 : 5
            if !(moved >= 10 || (dt >= minInterval && moved >= 2) || dt >= 30) { return }
        }
        lastPublished = (fix.timestamp, fix)
        guard liveConnected, iAmSharing, let live = store.live else { return }
        let position = LivePosition(userId: me.id, latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                                    accuracy: fix.horizontalAccuracy, heading: fix.course >= 0 ? fix.course : nil,
                                    timestamp: fix.timestamp.timeIntervalSince1970)
        Task { await live.publish(position) }
        if follow == .me { recenter() }
    }

    /// Receiver-side validation: reject malformed, stale or implausible fixes. Nothing is invented to hide a gap.
    private func receive(_ p: LivePosition) {
        guard (-90...90).contains(p.latitude), (-180...180).contains(p.longitude), p.accuracy >= 0, p.accuracy <= 200 else { return }
        guard NYCGeo.isNearCity(Coordinate(p.coordinate)) else { return }
        let age = Date().timeIntervalSince(p.date)
        guard age <= 60, age >= -30 else { return }
        if let prev = previousPartner {
            let dt = p.timestamp - prev.timestamp
            if dt <= 0 { return }
            let d = CLLocation(latitude: prev.latitude, longitude: prev.longitude).distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d / dt > 12 { return }
        }
        previousPartner = p
        partnerPosition = p
        partnerTrack.move(to: p.coordinate)
        pulseMarkers()
        partnerSeenAt = Date()
        if follow == .both { frameBoth() }
    }

    private func pulseMarkers() {
        markersAnimating = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(MarkerTrack.duration + 0.2))
            self?.markersAnimating = false
        }
    }

    /// The person moved the map by hand: stop following until they tap Recenter.
    func userPannedMap() { if follow != .free { follow = .free } }

    // MARK: Camera

    func frameRoute() {
        guard let coords = route?.coordinates, coords.count >= 2 else { return }
        camera = .rect(ActivityDetailViewModel.rect(for: coords))
    }

    func recenter() {
        switch follow {
        case .me:
            if let here = tracker.latest {
                camera = .camera(MapCamera(centerCoordinate: here.coordinate, distance: 650, heading: ExploreViewModel.gridHeading, pitch: 60))
            }
        case .both: frameBoth()
        case .route: frameRoute()
        case .free: break
        }
    }

    private func frameBoth() {
        var points = [tracker.latest?.coordinate, partnerPosition?.coordinate].compactMap { $0 }.map { Coordinate($0) }
        if points.count < 2 { if let c = points.first { points.append(Coordinate(c.latitude + 0.0004, c.longitude)) } else { return } }
        let rect = ActivityDetailViewModel.rect(for: points)
        camera = .rect(rect.insetBy(dx: -rect.size.width * 0.6 - 200, dy: -rect.size.height * 0.6 - 200))
    }

    func setFollow(_ mode: Follow) {
        follow = mode
        alongWithAnimation { recenter() }
    }
}

// MARK: - Marker animation

/// Interpolates a marker between two REAL fixes over a short duration so it glides instead of jumping.
/// It never extrapolates past the latest fix and never invents positions.
struct MarkerTrack: Equatable {
    var from: CLLocationCoordinate2D?
    var to: CLLocationCoordinate2D?
    var startedAt = Date.distantPast
    static let duration: TimeInterval = 1.0

    static func == (a: MarkerTrack, b: MarkerTrack) -> Bool {
        a.from?.latitude == b.from?.latitude && a.from?.longitude == b.from?.longitude
            && a.to?.latitude == b.to?.latitude && a.to?.longitude == b.to?.longitude && a.startedAt == b.startedAt
    }

    mutating func move(to next: CLLocationCoordinate2D, now: Date = .now) {
        from = coordinate(at: now) ?? next
        to = next
        startedAt = now
    }

    func coordinate(at date: Date) -> CLLocationCoordinate2D? {
        guard let to else { return nil }
        guard let from else { return to }
        let t = min(max(date.timeIntervalSince(startedAt) / Self.duration, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return CLLocationCoordinate2D(latitude: from.latitude + (to.latitude - from.latitude) * eased,
                                      longitude: from.longitude + (to.longitude - from.longitude) * eased)
    }

    func isAnimating(at date: Date) -> Bool { to != nil && date.timeIntervalSince(startedAt) < Self.duration + 0.1 }
}
