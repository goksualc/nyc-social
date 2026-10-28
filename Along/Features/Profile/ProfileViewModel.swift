import SwiftUI

@MainActor @Observable
final class ProfileViewModel {
    let store: AppStore
    var isEditing = false

    init(store: AppStore) { self.store = store }

    var me: User { store.me }

    func toggle(_ interest: Interest) async {
        var u = me
        if let i = u.interests.firstIndex(of: interest) { u.interests.remove(at: i) } else { u.interests.append(interest) }
        Haptics.selection()
        await store.updateProfile(u, silent: true)
    }

    func toggle(_ purpose: AlongPurpose) async {
        var u = me
        if u.alongFor.contains(purpose) {
            guard u.alongFor.count > 1 else { return }   // keep at least one
            u.alongFor.remove(purpose)
        } else { u.alongFor.insert(purpose) }
        Haptics.selection()
        await store.updateProfile(u, silent: true)
    }
}

enum SettingsDestination: Hashable {
    case visibility, location, notifications, blocked, about
}
