import SwiftUI

@MainActor @Observable
final class PlansViewModel {
    private let store: AppStore
    var segment = 0   // 0 Upcoming, 1 Past

    init(store: AppStore) { self.store = store }

    var items: [PlanItem] { store.plans(upcoming: segment == 0) }

    func host(of item: PlanItem) -> User? { store.host(of: item.activity) }

    func hostLabel(for item: PlanItem) -> String {
        item.role == .host ? "Hosted by you" : "Hosted by \(host(of: item)?.firstName ?? "someone")"
    }

    func status(for item: PlanItem) -> String {
        let a = item.activity
        let live = a.isActive(at: store.now)
        switch item.role {
        case .host:
            if a.isCancelled { return "Cancelled" }
            if !live { return "Completed" }
            let n = store.pendingRequests(for: a.id).count
            return n > 0 ? "\(n) request\(n == 1 ? "" : "s") pending" : a.spotsLabel
        case .accepted: return live ? "You're in" : "Completed"
        case .pending: return "Request pending"
        case .declined: return "Declined"
        }
    }

    func actionTitle(for item: PlanItem) -> String? {
        guard segment == 0 else { return nil }
        return item.role == .host ? "Manage Plan" : "View Plan"
    }
}
