import SwiftUI
import MapKit

@MainActor @Observable
final class CreateActivityViewModel {
    private let store: AppStore

    // Shared
    var start: Date
    var duration: TimeInterval = 2 * 3600
    var spots = 2
    var note = ""
    var meetingDetails = ""
    var hostMode: HostMode = .publicHost
    var isPublishing = false

    // Walk
    var from: Place?
    var to: Place?
    var pace: Pace = .casual
    var route: RoutePreview?
    var routeCamera: MapCameraPosition = .automatic

    // What's on your mind (optional, free text) and optional topic tags
    var mindPrompt = ""
    var tags: [String] = []

    /// Who the walk shows as its host. Every walk is on the map for everyone; this is only about the host's identity.
    enum HostMode: String, CaseIterable, Identifiable {
        case publicHost = "Public", privateHost = "Private Host", anonymousHost = "Anonymous Host"
        var id: String { rawValue }
        var detail: String {
            switch self {
            case .publicHost: "Everyone can see you: your name, photo and profile."
            case .privateHost: "Your walk is visible, but your name and photo stay hidden."
            case .anonymousHost: "Your walk is visible with minimal host details: no name, photo or tags."
            }
        }
        var hidesIdentity: Bool { self != .publicHost }
    }

    static let tagOptions = ["Tech", "Startups", "Life", "Creativity", "Literature", "Career", "Random Thoughts", "Psychology"]
    static let maxTags = 3

    func toggleTag(_ tag: String) {
        if let i = tags.firstIndex(of: tag) { tags.remove(at: i) }
        else if tags.count < Self.maxTags { tags.append(tag) }
    }

    /// Tags go with the walk, except for "Anonymous Host", which shares nothing beyond the walk itself.
    var publishedTags: [String] { hostMode == .anonymousHost ? [] : Array(tags.prefix(Self.maxTags)) }

    init(store: AppStore) {
        self.store = store
        let soon = Date().addingTimeInterval(45 * 60)
        let cal = Calendar.current
        let minute = cal.component(.minute, from: soon)
        self.start = cal.date(byAdding: .minute, value: (30 - minute % 30) % 30, to: soon).map { cal.date(bySetting: .second, value: 0, of: $0)! } ?? soon
    }

    // MARK: Derived

    var end: Date {
        get { start.addingTimeInterval(duration) }
        set { duration = max(newValue.timeIntervalSince(start), 15 * 60) }
    }

    var routeIsValid: Bool {
        guard let from, let to else { return false }
        return from.coordinate.distance(to: to.coordinate) > 50
    }
    var walkIsValid: Bool { routeIsValid }

    /// "Midtown → West Village · 32 min · 1.7 miles" once there's a route (nothing is shown until both ends are chosen).
    var routeLine: String? {
        guard let from, let to, routeIsValid, let route else { return nil }
        let miles = route.distance / 1609.344
        let minutes = max(Int((route.travelTime / 60).rounded()), 1)
        return String(format: "%@ → %@ · %d min · %.1f miles", from.publicLabel, to.publicLabel, minutes, miles) + (route.isEstimate ? " (estimate)" : "")
    }

    var walkHint: String? {
        guard let from, let to, !routeIsValid else { return nil }
        _ = (from, to)
        return "Start and destination need to be different."
    }

    // MARK: Route preview

    func updateRoute() async {
        guard let from, let to, routeIsValid else { route = nil; return }
        let preview = await RouteService.walkingRoute(from: from.coordinate, to: to.coordinate)
        route = preview
        routeCamera = .rect(ActivityDetailViewModel.rect(for: preview.coordinates))
    }

    /// Keeps the first and last vertex and an even spread between (the server accepts up to 1,000).
    static func downsample(_ coords: [Coordinate], to limit: Int) -> [Coordinate] {
        guard coords.count > limit, limit >= 2 else { return coords }
        let step = Double(coords.count - 1) / Double(limit - 1)
        return (0..<limit).map { coords[min(Int((Double($0) * step).rounded()), coords.count - 1)] }
    }

    // MARK: Publish

    private func daypart(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) { case ..<12: "Morning"; case ..<17: "Afternoon"; default: "Evening" }
    }

    private var walkTitle: String {
        guard let to else { return "Walk" }
        return "\(daypart(start)) walk to \(to.publicLabel)"
    }

    func publishWalk() async -> Bool {
        guard let from, let to, walkIsValid else { return false }
        let draft = ActivityDraft(
            title: walkTitle,
            walk: WalkInfo(from: from, to: to, pace: pace),
            startDate: start, endDate: start.addingTimeInterval(max(RouteService.estimate(from.coordinate, to.coordinate).travelTime, 30 * 60)),
            visibility: .public, capacity: spots,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingDetails: meetingDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            routeCoordinates: route.map { $0.isEstimate ? [] : Self.downsample($0.coordinates, to: 400) } ?? [],
            anonymousHost: hostMode.hidesIdentity, hostInterests: publishedTags,
            mindPrompt: mindPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        return await publish(draft)
    }

    private func publish(_ draft: ActivityDraft) async -> Bool {
        isPublishing = true
        defer { isPublishing = false }
        return await store.create(draft)
    }
}
