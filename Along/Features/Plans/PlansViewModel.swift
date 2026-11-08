import SwiftUI

/// The Walks tab: discover upcoming walks (yours and other people's public ones) and keep track of the ones you're in.
@MainActor @Observable
final class PlansViewModel {
    enum Filter: String, CaseIterable, Hashable { case upcoming = "Upcoming", tonight = "Tonight", past = "Past" }

    /// One row on the screen: a walk and, if it's mine, my role in it.
    struct Entry: Identifiable {
        let activity: Activity
        let role: PlanRole?
        var id: ID { activity.id }
    }

    private let store: AppStore
    var filter: Filter = .upcoming
    var query = ""

    init(store: AppStore) { self.store = store }

    /// Everything that matches the filter and the search text, soonest first (newest first for Past).
    var entries: [Entry] {
        let now = store.now
        var result: [Entry]
        if filter == .past {
            result = store.plans(upcoming: false).map { Entry(activity: $0.activity, role: $0.role) }
        } else {
            let mine = store.plans(upcoming: true)
            var seen = Set(mine.map(\.id))
            result = mine.map { Entry(activity: $0.activity, role: $0.role) }
            for a in store.discoverable where a.isActive(at: now) && !seen.contains(a.id) {   // other people's public walks
                seen.insert(a.id)
                result.append(Entry(activity: a, role: nil))
            }
            if filter == .tonight { result = result.filter { ExploreViewModel.isTonight($0.activity, now: now) } }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { result = result.filter { matches($0.activity, q) } }
        return result.sorted { filter == .past ? $0.activity.startDate > $1.activity.startDate : $0.activity.startDate < $1.activity.startDate }
    }

    /// The large photo card: the soonest walk, when nothing is being searched.
    var featured: Entry? { query.isEmpty && filter != .past ? entries.first : nil }
    var rest: [Entry] { featured == nil ? entries : Array(entries.dropFirst()) }

    /// Searches the title, route, neighbourhood, topic and host name (all fields the walk already shows publicly).
    private func matches(_ a: Activity, _ q: String) -> Bool {
        let haystack = [a.title, a.walk.from.publicLabel, a.walk.to.publicLabel, a.walk.from.area, a.walk.to.area,
                        a.mindPrompt ?? "", a.note,
                        store.host(of: a)?.firstName ?? ""]
        return haystack.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    func host(of entry: Entry) -> User? { store.host(of: entry.activity) }

    /// "Hosting", "You're in", "Request pending"… for my own walks; open spots for everyone else's.
    func badge(for entry: Entry) -> String? {
        let a = entry.activity
        let live = a.isActive(at: store.now)
        switch entry.role {
        case .host:
            if a.isCancelled { return "Cancelled" }
            if !live { return "Hosted" }
            let n = store.pendingRequests(for: a.id).count
            return n > 0 ? "\(n) request\(n == 1 ? "" : "s")" : "Hosting"
        case .accepted: return live ? "You're in" : "Joined"
        case .pending: return "Requested"
        case .declined: return "Declined"
        case .none: return nil
        }
    }

    /// Spots, or how the walk ended.
    func availability(for entry: Entry) -> String {
        entry.activity.isActive(at: store.now) ? entry.activity.spotsLabel : "Completed"
    }

    var now: Date { store.now }
    func refresh() async { await store.refresh() }
}
