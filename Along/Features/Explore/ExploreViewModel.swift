import SwiftUI
import MapKit

@MainActor @Observable
final class ExploreViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", walks = "Walks", cowork = "Cowork", today = "Today", tomorrow = "Tomorrow"
        var id: String { rawValue }
    }

    private let store: AppStore
    private let location: LocationService

    var filter: Filter = .all
    var selectedID: ID?
    var camera: MapCameraPosition = ExploreViewModel.overview
    var detent: SheetDetent = {
        switch LaunchOptions.current.detent { case "half": .half; case "full": .full; default: .collapsed }
    }()
    var sheetHeight: CGFloat = 96
    var presented: IDItem?
    var isCreating = false
    var createKind: ActivityKind?
    var locateIssue: String?

    /// Visible map area; drives which plans are fetched. Starts on all of Manhattan.
    private var visibleRegion = ExploreViewModel.overviewRegion
    private var lastSubmitted: DiscoveryQuery?
    private var debounce: Task<Void, Never>?

    init(store: AppStore, location: LocationService) {
        self.store = store
        self.location = location
        if let id = LaunchOptions.current.select {
            selectedID = id
            if let a = store.discoverable.first(where: { $0.id == id }) { camera = Self.selectionCamera(for: a) }
        }
        if let id = LaunchOptions.current.open { presented = IDItem(id: id) }
        if let kind = LaunchOptions.current.create { isCreating = true; createKind = kind == "cowork" ? .cowork : .walk }
    }

    /// Manhattan's street grid is rotated ~29° from north; aligning the camera to it makes the 3D city read cleanly.
    static let gridHeading: Double = 29

    static let overview: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7480, longitude: -73.9900), distance: 9000,
        heading: gridHeading, pitch: 50))

    nonisolated static let overviewRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7650, longitude: -73.9800),
        span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.09))

    static let bounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.7900, longitude: -73.9700),
                                                   span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.07)),
        minimumDistance: 400, maximumDistance: 45000)

    // MARK: Data

    /// The server applies the same filter to the query; filtering again here makes pill taps feel instant
    /// while the new page loads.
    var activities: [Activity] {
        let window = Self.window(for: filter, now: store.now)
        return store.discoverable.filter { a in
            if filter == .walks && a.kind != .walk { return false }
            if filter == .cowork && a.kind != .cowork { return false }
            if let to = window.to, a.startDate >= to { return false }
            if let from = window.from, a.endDate <= from { return false }
            return true
        }
        .sorted { $0.startDate < $1.startDate }
    }

    var isLoading: Bool { store.discoveryState == .loading }
    var loadError: String? { if case .failed(let m) = store.discoveryState, store.discoverable.isEmpty { m } else { nil } }

    /// "Today" / "Tomorrow" are overlap windows, so a session already under way still counts as today.
    nonisolated static func window(for filter: Filter, now: Date, calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        let startOfToday = calendar.startOfDay(for: now)
        switch filter {
        case .today:
            return (now, calendar.date(byAdding: .day, value: 1, to: startOfToday))
        case .tomorrow:
            let start = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
            return (start, calendar.date(byAdding: .day, value: 2, to: startOfToday))
        default:
            return (nil, calendar.date(byAdding: .day, value: 21, to: now))   // "All" looks three weeks ahead
        }
    }

    /// Visible rectangle (padded 15% so small pans don't refetch), capped to what the server accepts.
    nonisolated static func query(region: MKCoordinateRegion, filter: Filter, now: Date) -> DiscoveryQuery {
        let latHalf = min(region.span.latitudeDelta, 0.5) / 2 * 1.15
        let lngHalf = min(region.span.longitudeDelta, 0.5) / 2 * 1.15
        let w = window(for: filter, now: now)
        return DiscoveryQuery(
            minLat: region.center.latitude - latHalf, minLng: region.center.longitude - lngHalf,
            maxLat: region.center.latitude + latHalf, maxLng: region.center.longitude + lngHalf,
            kind: filter == .walks ? .walk : filter == .cowork ? .cowork : nil,
            from: w.from, to: w.to, limit: 50, offset: 0)
    }

    // MARK: Fetching

    /// Called when the map settles. Debounced so a flurry of pans costs one request.
    func regionChanged(_ region: MKCoordinateRegion) {
        visibleRegion = region
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// Fetches the first page for the current area + filter (skips identical back-to-back queries).
    func reload(force: Bool = false) async {
        var q = Self.query(region: visibleRegion, filter: filter, now: store.now)
        q.from = q.from.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded(.down) * 60) }   // ignore sub-minute drift
        if !force, let last = lastSubmitted, Self.sameArea(last, q), last.kind == q.kind,
           last.from == q.from, last.to == q.to, store.discoveryState != .idle {
            if case .failed = store.discoveryState {} else { return }
        }
        lastSubmitted = q
        await store.discover(q)
    }

    private static func sameArea(_ a: DiscoveryQuery, _ b: DiscoveryQuery) -> Bool {
        abs(a.minLat - b.minLat) < 0.0005 && abs(a.maxLat - b.maxLat) < 0.0005
            && abs(a.minLng - b.minLng) < 0.0005 && abs(a.maxLng - b.maxLng) < 0.0005
    }

    var walks: [Activity] { activities.filter { $0.kind == .walk } }

    var selected: Activity? {
        guard let id = selectedID else { return nil }
        return activities.first { $0.id == id }
    }

    func host(of a: Activity) -> User? { store.host(of: a) }

    var emptyState: (title: String, message: String, action: String?, kind: ActivityKind?) {
        switch filter {
        case .walks: ("No walks around here yet.", "Be the first to make a plan.", "Create a Walk", .walk)
        case .cowork: ("No cowork sessions yet.", "Be the first to make a plan.", "Create a Session", .cowork)
        case .today: ("Nothing planned for today.", "Be the first to make a plan.", "Create a Plan", nil)
        case .tomorrow: ("Nothing planned for tomorrow.", "Be the first to make a plan.", "Create a Plan", nil)
        case .all: ("No plans around here yet.", "Be the first to make a plan.", "Create a Plan", nil)
        }
    }

    // MARK: Actions

    func setFilter(_ f: Filter) {
        alongWithAnimation { filter = f; if selected == nil { selectedID = nil } }
        Task { await reload() }
    }

    func select(_ a: Activity) {
        Haptics.light()
        alongWithAnimation {
            selectedID = a.id
            detent = .collapsed
            // Shift the centre "down-screen" (opposite the camera heading) so the marker sits above the card.
            camera = Self.selectionCamera(for: a)
        }
    }

    static func selectionCamera(for a: Activity) -> MapCameraPosition {
        let c = a.mapCoordinate
        let distance = 1800.0
        let shift = distance * 0.55 / 111_000
        let rad = (gridHeading + 180) * .pi / 180
        let center = CLLocationCoordinate2D(latitude: c.latitude + cos(rad) * shift,
                                            longitude: c.longitude + sin(rad) * shift / cos(c.latitude * .pi / 180))
        return .camera(MapCamera(centerCoordinate: center, distance: distance, heading: gridHeading, pitch: 60))
    }

    /// "1.2 miles" from the user's last known location, or nil when location isn't available.
    func distanceLabel(to a: Activity) -> String? {
        guard let here = location.lastLocation else { return nil }
        let m = CLLocation(latitude: here.cl.latitude, longitude: here.cl.longitude)
            .distance(from: CLLocation(latitude: a.mapCoordinate.latitude, longitude: a.mapCoordinate.longitude))
        let miles = m / 1609.34
        return miles < 0.1 ? "Nearby" : String(format: "%.1f %@", miles, (miles * 10).rounded() == 10 ? "mile" : "miles")
    }

    /// The closest other plans to `a` (within 2 km), nearest first.
    func nearby(to a: Activity, limit: Int = 3) -> [Activity] {
        let here = CLLocation(latitude: a.mapCoordinate.latitude, longitude: a.mapCoordinate.longitude)
        return activities.filter { $0.id != a.id }
            .map { ($0, here.distance(from: CLLocation(latitude: $0.mapCoordinate.latitude, longitude: $0.mapCoordinate.longitude))) }
            .filter { $0.1 <= 2000 }.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    func deselect() {
        guard selectedID != nil else { return }
        alongWithAnimation { selectedID = nil }
    }

    func open(_ a: Activity) {
        Haptics.light()
        presented = IDItem(id: a.id)
    }

    func startCreating(_ kind: ActivityKind? = nil) {
        createKind = kind
        isCreating = true
    }

    /// Asks for permission only now, then flies to the approximate location if it's in Manhattan.
    func locateMe() async {
        guard store.settings.useLocationToCenterMap else {
            store.showToast("Location is off in Privacy settings", symbol: "location.slash")
            return
        }
        guard let here = await location.locate() else {
            store.showToast(location.isDenied ? "Location access is off for Along" : "Couldn't find your location",
                            symbol: "location.slash")
            return
        }
        guard ManhattanGeo.contains(here) else {
            alongWithAnimation { camera = Self.overview }
            store.showToast("You're outside Manhattan. Along is Manhattan-only for now.", symbol: "mappin.slash")
            return
        }
        Haptics.light()
        alongWithAnimation { camera = .camera(MapCamera(centerCoordinate: here.cl, distance: 2500, heading: Self.gridHeading, pitch: 55)) }
    }
}
