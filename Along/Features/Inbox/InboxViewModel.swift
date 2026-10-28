import SwiftUI

@MainActor @Observable
final class InboxViewModel {
    let store: AppStore
    var segment = 0   // 0 Requests, 1 Messages
    var profile: IDItem?

    init(store: AppStore) { self.store = store }

    var requests: [JoinRequest] { store.incomingRequests }
    var conversations: [Conversation] { store.conversations() }
    var pendingCount: Int { store.pendingIncomingCount }

    func user(_ id: ID) -> User? { store.user(id) }
    func activity(_ id: ID) -> Activity? { store.activity(id) }

    func headline(for r: JoinRequest) -> String {
        let name = user(r.requesterID)?.firstName ?? "Someone"
        let noun = activity(r.activityID)?.kind == .cowork ? "session" : "walk"
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
