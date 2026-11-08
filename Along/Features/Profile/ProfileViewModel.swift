import SwiftUI

@MainActor @Observable
final class ProfileViewModel {
    let store: AppStore
    var isEditing = false

    init(store: AppStore) { self.store = store }

    var me: User { store.me }

    private(set) var stats: WalkStats?

    private(set) var recentWalks: [CompletedWalk] = []

    /// Real totals and the latest completed walks, from the same history the Walk History screen uses.
    func loadStats() async {
        stats = try? await store.walks.stats()
        recentWalks = Array(((try? await store.walks.history()) ?? []).prefix(6))
    }
}

enum SettingsDestination: Hashable {
    case home, visibility, location, notifications, blocked, about, history
}
