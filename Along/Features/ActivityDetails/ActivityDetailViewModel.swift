import SwiftUI
import MapKit

@MainActor @Observable
final class ActivityDetailViewModel {
    let store: AppStore
    let activityID: ID

    var route: RoutePreview?
    var routeCamera: MapCameraPosition = .automatic
    var profile: IDItem?
    var confirmCancel = false
    var confirmLeave = false
    var confirmBlock = false
    var showReport = false
    var showEdit = false
    var isWorking = false

    init(store: AppStore, activityID: ID) {
        self.store = store
        self.activityID = activityID
    }

    var activity: Activity? { store.activity(activityID) }
    var host: User? { activity.flatMap(store.host(of:)) }
    var isHost: Bool { activity.map(store.isHost) ?? false }
    var role: PlanRole? { activity.flatMap(store.role(in:)) }
    var isLive: Bool { activity?.isActive(at: store.now) ?? false }
    var pendingRequests: [JoinRequest] { store.pendingRequests(for: activityID) }
    var participants: [User] { activity.map(store.participants(of:)) ?? [] }

    /// The chat with the host (for guests) once accepted.
    var hostConversation: Conversation? {
        guard let a = activity else { return nil }
        return store.conversation(for: a.id, with: a.hostID).flatMap { store.isOpen($0) ? $0 : nil }
    }
    func conversation(with user: User) -> Conversation? {
        store.conversation(for: activityID, with: user.id).flatMap { store.isOpen($0) ? $0 : nil }
    }

    // MARK: Route

    func loadRoute() async {
        guard let activity, let walk = activity.walk else { return }
        // The host's saved route (shared with accepted guests) beats re-asking MapKit.
        if activity.routeCoordinates.count >= 2 {
            let coords = activity.routeCoordinates
            let length = zip(coords, coords.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            route = RoutePreview(coordinates: coords, distance: length, travelTime: length / 1.35, isEstimate: false)
            routeCamera = .rect(Self.rect(for: coords))
            return
        }
        let preview = await RouteService.walkingRoute(from: walk.from.coordinate, to: walk.to.coordinate)
        route = preview
        routeCamera = .rect(Self.rect(for: preview.coordinates))
    }

    static func rect(for coordinates: [Coordinate]) -> MKMapRect {
        let rect = coordinates.reduce(MKMapRect.null) { r, c in
            r.union(MKMapRect(origin: MKMapPoint(c.cl), size: MKMapSize(width: 0, height: 0)))
        }
        let pad = max(rect.width, rect.height) * 0.35 + 250
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    // MARK: Actions

    func requestToJoin() async {
        guard let a = activity else { return }
        isWorking = true
        await store.requestToJoin(a)
        isWorking = false
    }

    func withdraw() async { if let a = activity { await store.withdrawRequest(a) } }
    func leave() async { if let a = activity { await store.leave(a) } }
    func cancel() async { if let a = activity { await store.cancel(a) } }
    func respond(_ request: JoinRequest, accept: Bool) async { await store.respond(to: request, accept: accept) }
    func report(_ reason: ReportReason) async { await store.report(.activity(activityID), reason: reason) }
    func blockHost() async { if let h = host { await store.block(h.id) } }
}
