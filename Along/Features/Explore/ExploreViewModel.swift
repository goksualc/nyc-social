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

    init(store: AppStore, location: LocationService) {
        self.store = store
        self.location = location
        if let id = LaunchOptions.current.select { selectedID = id }
        if let id = LaunchOptions.current.open { presented = IDItem(id: id) }
        if let kind = LaunchOptions.current.create { isCreating = true; createKind = kind == "cowork" ? .cowork : .walk }
    }

    static let overview: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.7530, longitude: -73.9850), distance: 25000))

    static let bounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.7900, longitude: -73.9700),
                                                   span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.07)),
        minimumDistance: 400, maximumDistance: 45000)

    // MARK: Data

    var activities: [Activity] {
        store.discoverable.filter { a in
            switch filter {
            case .all: true
            case .walks: a.kind == .walk
            case .cowork: a.kind == .cowork
            case .today: ActivityTime.isToday(a.startDate, now: store.now)
            case .tomorrow: ActivityTime.isTomorrow(a.startDate, now: store.now)
            }
        }
        .sorted { $0.startDate < $1.startDate }
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
    }

    func select(_ a: Activity) {
        Haptics.light()
        alongWithAnimation {
            selectedID = a.id
            detent = .collapsed
            // Nudge the centre south so the marker sits above the preview card.
            let c = a.mapCoordinate
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: c.latitude - 0.0035, longitude: c.longitude), distance: 4500))
        }
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
        alongWithAnimation { camera = .camera(MapCamera(centerCoordinate: here.cl, distance: 3000)) }
    }
}
