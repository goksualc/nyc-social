import SwiftUI
import MapKit

@MainActor @Observable
final class ExploreViewModel {
    /// Which day's walks to show. Days are New York calendar days, whatever time zone the phone is in.
    enum DateFilter: Equatable, Hashable {
        case all, today, tomorrow
        /// Any instant inside the chosen New York day.
        case day(Date)
    }

    private let store: AppStore
    private let location: LocationService

    var dateFilter: DateFilter = .all
    var selectedID: ID?
    private(set) var openClusterWalkIDs: [ID] = []
    private(set) var openClusterKey: String?
    var isClusterOpen: Bool { get { openClusterKey != nil } set { if !newValue { closeCluster() } } }
    var camera: MapCameraPosition = ExploreViewModel.overview
    var detent: SheetDetent = {
        switch LaunchOptions.current.detent { case "half": .half; case "full": .full; default: .collapsed }
    }()
    var sheetHeight: CGFloat = 96
    var presented: IDItem?
    var isCreating = false
    var locateIssue: String?
    /// Visible latitude span in degrees; drives clustering.
    private(set) var zoomSpan: Double = 0.45
    /// The walking route of the selected walk (MapKit directions, or the saved route for members).
    private(set) var selectedRoute: RoutePreview?
    private var routeCache: [ID: RoutePreview] = [:]
    private var routeTask: Task<Void, Never>?

    /// Visible map area; drives which plans are fetched. Starts on all five boroughs.
    private var visibleRegion = ExploreViewModel.overviewRegion
    private var lastSubmitted: DiscoveryQuery?
    private var debounce: Task<Void, Never>?

    init(store: AppStore, location: LocationService) {
        self.store = store
        self.location = location
        if let id = LaunchOptions.current.select {
            selectedID = id
            if let a = store.activity(id) { camera = Self.selectionCamera(for: a); loadRoute(for: a) }
        }
        if let id = LaunchOptions.current.open { presented = IDItem(id: id) }
        if LaunchOptions.current.create != nil { isCreating = true }
    }

    /// Manhattan's street grid is rotated ~29° from north; aligning the camera to it makes the 3D city read cleanly there.
    /// The other boroughs' grids differ, so the camera faces north everywhere else.
    static let gridHeading: Double = 29
    static func heading(near c: Coordinate) -> Double { NYCGeo.borough(of: c) == "Manhattan" ? gridHeading : 0 }

    /// All five boroughs at once, tilted just enough to keep the 3D look without hiding the outer boroughs behind Manhattan.
    static let overview: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9300), distance: 88000,
        heading: 0, pitch: 22))

    nonisolated static let overviewRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7000, longitude: -73.9700),
        span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.50))

    static let bounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.7100, longitude: -73.9700),
                                                   span: MKCoordinateSpan(latitudeDelta: 0.52, longitudeDelta: 0.62)),
        minimumDistance: 400, maximumDistance: 170000)

    // MARK: Data

    /// Everything the map can show for the current date filter. The date range is also what the server is asked for (see `query`),
    /// so a day far in the future is fetched, not merely hidden.
    var activities: [Activity] {
        let now = store.now
        return store.discoverable.filter { Self.matches($0, dateFilter, now: now) }.sorted { $0.startDate < $1.startDate }
    }

    // MARK: New York days

    nonisolated static let newYork: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// The half-open interval [midnight, next midnight) of a New York day. Using the calendar (not `+ 24 h`) keeps the
    /// 23- and 25-hour days around daylight saving correct. The Dates are absolute instants, so they convert to UTC for Supabase as-is.
    nonisolated static func dayInterval(for filter: DateFilter, now: Date) -> DateInterval? {
        let cal = newYork
        let anchor: Date
        switch filter {
        case .all: return nil
        case .today: anchor = now
        case .tomorrow: anchor = cal.date(byAdding: .day, value: 1, to: now)!
        case .day(let d): anchor = d
        }
        let start = cal.startOfDay(for: anchor)
        return DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!)
    }

    /// A walk belongs to a day when it overlaps it (one already under way at midnight still counts for both days).
    nonisolated static func matches(_ a: Activity, _ f: DateFilter, now: Date) -> Bool {
        guard let day = dayInterval(for: f, now: now) else { return true }
        return a.endDate > day.start && a.startDate < day.end
    }

    /// 5 PM until 4 AM, New York time (used by the Walks tab's "Tonight").
    nonisolated static func isTonight(_ a: Activity, now: Date) -> Bool {
        let cal = newYork
        let evening = cal.date(byAdding: .hour, value: 17, to: cal.startOfDay(for: now))!
        let lateNight = cal.date(byAdding: .hour, value: 28, to: cal.startOfDay(for: now))!
        return a.endDate > max(now, evening) && a.startDate < lateNight
    }

    /// "Nov 12" for the chosen day.
    func label(for filter: DateFilter) -> String? {
        guard case .day(let d) = filter else { return nil }
        let f = DateFormatter()
        f.calendar = Self.newYork
        f.timeZone = Self.newYork.timeZone
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: d)
    }

    var isLoading: Bool { store.discoveryState == .loading }
    var loadError: String? { if case .failed(let m) = store.discoveryState, store.discoverable.isEmpty { m } else { nil } }

    /// The time window sent to the server: the chosen day, or the next three weeks.
    nonisolated static func window(for filter: DateFilter, now: Date) -> (from: Date?, to: Date?) {
        if let day = dayInterval(for: filter, now: now) { return (day.start, day.end) }
        return (nil, Calendar.current.date(byAdding: .day, value: 21, to: now))
    }

    /// Visible rectangle (padded 15% so small pans don't refetch), capped to what the server accepts.
    nonisolated static func query(region: MKCoordinateRegion, filter: DateFilter, now: Date) -> DiscoveryQuery {
        let latHalf = min(region.span.latitudeDelta, 0.5) / 2 * 1.15
        let lngHalf = min(region.span.longitudeDelta, 0.5) / 2 * 1.15
        let w = window(for: filter, now: now)
        return DiscoveryQuery(
            minLat: region.center.latitude - latHalf, minLng: region.center.longitude - lngHalf,
            maxLat: region.center.latitude + latHalf, maxLng: region.center.longitude + lngHalf,
            from: w.from, to: w.to, limit: 50, offset: 0)
    }

    // MARK: Fetching

    /// Called when the map settles. Debounced so a flurry of pans costs one request.
    func regionChanged(_ region: MKCoordinateRegion) {
        visibleRegion = region
        if abs(region.span.latitudeDelta - zoomSpan) > zoomSpan * 0.08 { zoomSpan = region.span.latitudeDelta }   // re-cluster only on real zoom changes
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// Fetches the first page for the current area + filter (skips identical back-to-back queries).
    func reload(force: Bool = false) async {
        var q = Self.query(region: visibleRegion, filter: dateFilter, now: store.now)
        q.from = q.from.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded(.down) * 60) }   // ignore sub-minute drift
        if !force, let last = lastSubmitted, Self.sameArea(last, q),
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

    var walks: [Activity] { activities }

    var selected: Activity? {
        // Looked up among everything the app knows (map walks and my own plans), so a selection survives panning away.
        guard let id = selectedID, let a = store.activity(id), a.isActive(at: store.now) else { return nil }
        return a
    }

    func host(of a: Activity) -> User? { store.host(of: a) }

    var emptyState: (title: String, message: String, action: String?) {
        switch dateFilter {
        case .all: ("No walks around here yet.", "Your next conversation is just around the block. Be the first to make a plan.", "Create a Walk")
        case .today: ("Nothing planned for today.", "Be the first to make a plan.", "Create a Walk")
        case .tomorrow: ("Nothing planned for tomorrow.", "Be the first to make a plan.", "Create a Walk")
        case .day: ("No walks that day.", "Try another date, or start one yourself.", "Create a Walk")
        }
    }

    // MARK: Clustering

    struct Cluster: Identifiable, Equatable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let activities: [Activity]
        static func == (a: Cluster, b: Cluster) -> Bool { a.id == b.id && a.activities.count == b.activities.count }
    }
    enum MapItem: Identifiable {
        case walk(Activity), cluster(Cluster)
        var id: String { switch self { case .walk(let a): "w-" + a.id; case .cluster(let c): "c-" + c.id } }
    }

    /// Walks as the map draws them: nearby walks merge into a numbered cluster while zoomed out, and split apart as you
    /// zoom in. The selected walk is never swallowed by a cluster. Counts come from real loaded walks.
    var mapItems: [MapItem] {
        var list = activities
        // The selected walk is always drawn, even if panning (or a different filter) took it out of the loaded set.
        if let sel = selected, !list.contains(where: { $0.id == sel.id }) { list.append(sel) }
        guard zoomSpan > 0.012, list.count > 1 else { return list.map { .walk($0) } }
        let cell = zoomSpan / 7
        var buckets: [String: [Activity]] = [:]
        var singles: [Activity] = []
        for a in list {
            if a.id == selectedID { singles.append(a); continue }
            let c = a.mapCoordinate
            buckets["\(Int((c.latitude / cell).rounded(.down)))_\(Int((c.longitude / cell).rounded(.down)))", default: []].append(a)
        }
        var items: [MapItem] = singles.map { .walk($0) }
        for (key, group) in buckets {
            if group.count == 1 { items.append(.walk(group[0])); continue }
            let lat = group.map { $0.mapCoordinate.latitude }.reduce(0, +) / Double(group.count)
            let lng = group.map { $0.mapCoordinate.longitude }.reduce(0, +) / Double(group.count)
            items.append(.cluster(Cluster(id: key + "-\(group.count)", coordinate: .init(latitude: lat, longitude: lng), activities: group)))
        }
        return items
    }

    /// Tapping a cluster lists its walks in a sheet. The camera is left alone: walks that share a spot never separate by
    /// zooming, so zooming could not be what makes them reachable.
    func openCluster(_ cluster: Cluster) {
        Haptics.light()
        openClusterWalkIDs = cluster.activities.map(\.id)
        openClusterKey = cluster.activities.map(\.id).sorted().joined(separator: ",")
    }

    func closeCluster() { openClusterWalkIDs = []; openClusterKey = nil }

    /// The cluster's walks, re-resolved each time so a filter change, a cancelled walk or a full one can't linger in the sheet.
    var clusterWalks: [Activity] {
        let visible = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return openClusterWalkIDs.compactMap { visible[$0] }.sorted { $0.startDate < $1.startDate }
    }

    func isHighlighted(_ cluster: Cluster) -> Bool {
        openClusterKey == cluster.activities.map(\.id).sorted().joined(separator: ",")
    }

    // MARK: Actions

    /// Changes the day. The camera stays where it is; only the walks (and the server query) change.
    func setDate(_ f: DateFilter) {
        guard f != dateFilter else { return }
        alongWithAnimation {
            dateFilter = f
            if let id = selectedID, selected == nil || !activities.contains(where: { $0.id == id }) { selectedID = nil; selectedRoute = nil }
        }
        Task { await reload(force: true) }
    }

    func select(_ a: Activity) {
        Haptics.light()
        alongWithAnimation {
            selectedID = a.id
            detent = .collapsed
            // Shift the centre "down-screen" (opposite the camera heading) so the marker sits above the card.
            camera = Self.selectionCamera(for: a)
        }
        loadRoute(for: a)
    }

    private func loadRoute(for a: Activity) {
        routeTask?.cancel()
        if a.routeCoordinates.count >= 2 {
            selectedRoute = RoutePreview(coordinates: a.routeCoordinates, distance: a.routeCoordinates.adjacentDistance(),
                                         travelTime: a.routeCoordinates.adjacentDistance() / 1.35, isEstimate: false)
            return
        }
        if let cached = routeCache[a.id] { selectedRoute = cached; return }
        selectedRoute = nil
        routeTask = Task { [weak self] in
            let route = await RouteService.walkingRoute(from: a.walk.from.coordinate, to: a.walk.to.coordinate)
            guard !Task.isCancelled, let self, self.selectedID == a.id else { return }
            if !route.isEstimate { self.routeCache[a.id] = route }
            alongWithAnimation { self.selectedRoute = route }
        }
    }

    /// Frames a walk so its pin sits in the open map between the header and the sheet, whatever the screen height.
    static func selectionCamera(for a: Activity, screenHeight: CGFloat = UIScreen.main.bounds.height) -> MapCameraPosition {
        let c = a.mapCoordinate
        let distance = 1800.0
        // The sheet is ~36% of the screen plus its fixed button/host rows; aim for the middle of what's left below the header.
        let headerBottom: CGFloat = 112
        let sheetTop = screenHeight - (screenHeight * 0.36 + 215)
        let target = headerBottom + (sheetTop - headerBottom) * 0.65
        let offsetPoints = max(screenHeight / 2 - target, 0)
        let metersPerPoint = 1 / 0.6                      // measured: ~0.6 screen points per metre at this distance and pitch
        let shift = distance * 0 + Double(offsetPoints * metersPerPoint) / 111_000
        let heading = heading(near: Coordinate(c))
        let rad = (heading + 180) * .pi / 180
        let center = CLLocationCoordinate2D(latitude: c.latitude + cos(rad) * shift,
                                            longitude: c.longitude + sin(rad) * shift / cos(c.latitude * .pi / 180))
        return .camera(MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 46))
    }

    /// "1.2 miles" from the user's last known location, or nil when location isn't available.
    func distanceLabel(to a: Activity) -> String? {
        guard let here = location.lastLocation else { return nil }
        let m = CLLocation(latitude: here.cl.latitude, longitude: here.cl.longitude)
            .distance(from: CLLocation(latitude: a.mapCoordinate.latitude, longitude: a.mapCoordinate.longitude))
        let miles = m / 1609.34
        return miles < 0.1 ? "Nearby" : String(format: "%.1f %@", miles, (miles * 10).rounded() == 10 ? "mile" : "miles")
    }

    func deselect() {
        guard selectedID != nil else { return }
        routeTask?.cancel()
        alongWithAnimation { selectedID = nil; selectedRoute = nil }
    }

    func open(_ a: Activity) {
        Haptics.light()
        presented = IDItem(id: a.id)
    }

    func startCreating() {
        isCreating = true
    }

    /// Asks for permission only now, then flies to the approximate location if it's in New York City.
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
        guard NYCGeo.contains(here) else {
            alongWithAnimation { camera = Self.overview }
            store.showToast("You're outside New York City. Along covers the five boroughs.", symbol: "mappin.slash")
            return
        }
        Haptics.light()
        alongWithAnimation { camera = .camera(MapCamera(centerCoordinate: here.cl, distance: 2500, heading: Self.heading(near: here), pitch: 55)) }
    }
}

extension Array where Element == Coordinate {
    /// Length of the polyline in metres.
    func adjacentDistance() -> Double { zip(self, dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
}
