import SwiftUI

@MainActor @Observable
final class InboxViewModel {
    let store: AppStore
    enum Filter: String, CaseIterable, Hashable { case all = "All", messages = "Messages", requests = "Requests", unread = "Unread" }
    var filter: Filter = LaunchOptions.current.inboxFilter.flatMap(Filter.init(rawValue:)) ?? .all
    var profile: IDItem?
    /// What's typed in the search field. Filtering is in memory over conversations that are already loaded, so typing never hits the network.
    var query = ""

    init(store: AppStore) { self.store = store }

    var requests: [JoinRequest] {
        let all = store.incomingRequests
        guard isSearching else { return all }
        return all.filter { r in
            Self.contains(user(r.requesterID)?.firstName, needle) || Self.contains(activity(r.activityID)?.title, needle)
        }
    }
    var conversations: [Conversation] { store.conversations() }
    var pendingCount: Int { store.pendingIncomingCount }
    var unreadCount: Int { store.unreadConversationCount }

    /// Chats shown for the current filter (Requests shows request cards instead).
    var visibleConversations: [Conversation] {
        let base: [Conversation]
        switch filter {
        case .all, .messages: base = conversations
        case .unread: base = conversations.filter(store.isUnread)
        case .requests: base = []
        }
        return isSearching ? base.filter(matches) : base      // `filter` keeps the store's ordering
    }

    // MARK: Search

    var isSearching: Bool { !needle.isEmpty }
    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Case- and diacritic-insensitive match on the other person's name, the latest message and the walk's title.
    /// The names come from the same store the rows use, so an anonymous organizer is only ever searchable as "Anonymous Walker".
    func matches(_ c: Conversation) -> Bool {
        let n = needle
        guard !n.isEmpty else { return true }
        return Self.contains(store.otherParticipant(in: c)?.firstName, n)
            || Self.contains(store.lastMessage(in: c)?.text, n)
            || Self.contains(activity(c.activityID)?.title, n)
    }

    private static func contains(_ text: String?, _ needle: String) -> Bool {
        text?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    func isUnread(_ c: Conversation) -> Bool { store.isUnread(c) }
    /// The walk a chat belongs to, but only while it's still ahead of you (that's when the preview card is useful).
    func upcomingWalk(for c: Conversation) -> Activity? {
        activity(c.activityID).flatMap { $0.isActive(at: store.now) ? $0 : nil }
    }

    func user(_ id: ID) -> User? { store.user(id) }
    func activity(_ id: ID) -> Activity? { store.activity(id) }

    func headline(for r: JoinRequest) -> String {
        let name = user(r.requesterID)?.firstName ?? "Someone"
        let noun = "walk"
        switch r.status {
        case .pending: return "\(name) wants to join your \(noun)"
        case .accepted: return "\(name) is joining your \(noun)"
        default: return "\(name) · \(noun)"
        }
    }

    func isFull(_ r: JoinRequest) -> Bool { activity(r.activityID)?.isFull ?? true }
    func isLive(_ r: JoinRequest) -> Bool { activity(r.activityID)?.isActive(at: store.now) ?? false }

    func respond(_ r: JoinRequest, accept: Bool) async { await store.respond(to: r, accept: accept) }
    func chat(for r: JoinRequest) -> Conversation? {
        guard let a = activity(r.activityID) else { return nil }
        return store.conversation(for: a.id, with: r.requesterID).flatMap { store.isOpen($0) ? $0 : nil }
    }
}
