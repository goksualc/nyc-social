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
    var visibility: Visibility = .public
    var isPublishing = false

    // Walk
    var from: Place?
    var to: Place?
    var pace: Pace = .casual
    var route: RoutePreview?
    var routeCamera: MapCameraPosition = .automatic

    // Cowork
    var venue: Place?
    var style: WorkStyle = .deepWork

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

    var walkIsValid: Bool {
        guard let from, let to else { return false }
        return from.coordinate.distance(to: to.coordinate) > 50
    }
    var coworkIsValid: Bool { venue != nil && duration >= 15 * 60 }

    var walkHint: String? {
        guard let from, let to, !walkIsValid else { return nil }
        _ = (from, to)
        return "Start and destination need to be different."
    }

    // MARK: Route preview

    func updateRoute() async {
        guard let from, let to, walkIsValid else { route = nil; return }
        let preview = await RouteService.walkingRoute(from: from.coordinate, to: to.coordinate)
        route = preview
        routeCamera = .rect(ActivityDetailViewModel.rect(for: preview.coordinates))
    }

    // MARK: Publish

    private func daypart(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) { case ..<12: "Morning"; case ..<17: "Afternoon"; default: "Evening" }
    }

    func publishWalk() async -> Bool {
        guard let from, let to else { return false }
        let draft = ActivityDraft(
            title: "\(daypart(start)) walk to \(to.publicLabel)",
            details: .walk(WalkInfo(from: from, to: to, pace: pace)),
            startDate: start, endDate: start.addingTimeInterval(max(RouteService.estimate(from.coordinate, to.coordinate).travelTime, 30 * 60)),
            visibility: visibility, capacity: spots,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingDetails: meetingDetails.trimmingCharacters(in: .whitespacesAndNewlines))
        return await publish(draft)
    }

    func publishCowork() async -> Bool {
        guard let venue else { return false }
        let draft = ActivityDraft(
            title: "Working from \(venue.area)",
            details: .cowork(CoworkInfo(venue: venue, style: style)),
            startDate: start, endDate: end, visibility: visibility, capacity: spots,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingDetails: meetingDetails.trimmingCharacters(in: .whitespacesAndNewlines))
        return await publish(draft)
    }

    private func publish(_ draft: ActivityDraft) async -> Bool {
        isPublishing = true
        defer { isPublishing = false }
        return await store.create(draft)
    }
}
