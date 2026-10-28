import SwiftUI

/// A role the signed-in user plays in a plan.
enum PlanRole: Hashable {
    case host, accepted, pending, declined
}

struct PlanItem: Identifiable, Hashable {
    let activity: Activity
    let role: PlanRole
    var id: ID { activity.id }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

/// Single source of truth for UI state. It mirrors the latest `AlongSnapshot` from the backend and
/// exposes derived, view-friendly queries. Mutations always go through the backend so the same code
/// path works when the backend becomes real.
@MainActor @Observable
final class AppStore {
    private let backend: any AlongBackend
    private(set) var snapshot: AlongSnapshot
    /// Advances once a minute so expired plans fall off the map without a relaunch.
    private(set) var now: Date = .now
    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?

    init(backend: any AlongBackend, snapshot: AlongSnapshot) {
        self.backend = backend
        self.snapshot = snapshot
    }

    static func bootstrap(backend: any AlongBackend = MockAlongBackend()) async -> AppStore {
        AppStore(backend: backend, snapshot: await backend.loadSnapshot())
    }

    // MARK: Lookups

    var me: User { snapshot.me }
    var settings: UserSettings { snapshot.settings }
    var blockedUsers: [User] { snapshot.users.filter { snapshot.blockedUserIDs.contains($0.id) } }

    func user(_ id: ID) -> User? { id == me.id ? me : snapshot.users.first { $0.id == id } }
    func activity(_ id: ID) -> Activity? { snapshot.activities.first { $0.id == id } }
    func isBlocked(_ id: ID) -> Bool { snapshot.blockedUserIDs.contains(id) }
    func host(of activity: Activity) -> User? { user(activity.hostID) }
    func isHost(_ activity: Activity) -> Bool { activity.hostID == me.id }
    func participants(of activity: Activity) -> [User] { activity.participantIDs.compactMap(user) }

    func requests(for activityID: ID) -> [JoinRequest] {
        snapshot.requests.filter { $0.activityID == activityID }.sorted { $0.createdAt > $1.createdAt }
    }
    func pendingRequests(for activityID: ID) -> [JoinRequest] {
        requests(for: activityID).filter { $0.status == .pending }
    }
    func myRequest(for activityID: ID) -> JoinRequest? {
        snapshot.requests.first { $0.activityID == activityID && $0.requesterID == me.id }
    }
    func role(in activity: Activity) -> PlanRole? {
        if isHost(activity) { return .host }
        switch myRequest(for: activity.id)?.status {
        case .accepted: return .accepted
        case .pending: return .pending
        case .declined: return .declined
        default: return nil
        }
    }

    // MARK: Discovery

    /// Public, live, not blocked. This is what the map and discovery list show.
    var discoverable: [Activity] {
        snapshot.activities.filter { $0.visibility == .public && $0.isActive(at: now) }
    }

    // MARK: Plans

    func plans(upcoming: Bool) -> [PlanItem] {
        let items: [PlanItem] = snapshot.activities.compactMap { a in
            guard let role = role(in: a) else { return nil }
            let live = a.isActive(at: now)
            if upcoming { return live && role != .declined ? PlanItem(activity: a, role: role) : nil }
            return !live || role == .declined ? PlanItem(activity: a, role: role) : nil
        }
        return items.sorted { upcoming ? $0.activity.startDate < $1.activity.startDate : $0.activity.startDate > $1.activity.startDate }
    }

    // MARK: Inbox

    /// Requests other people have sent for plans I host. Pending first, then newest.
    var incomingRequests: [JoinRequest] {
        snapshot.requests.filter { r in
            r.requesterID != me.id && r.status != .withdrawn
                && activity(r.activityID).map({ isHost($0) && $0.isActive(at: now) }) == true
        }.sorted {
            ($0.status == .pending ? 0 : 1, -$0.createdAt.timeIntervalSince1970) < ($1.status == .pending ? 0 : 1, -$1.createdAt.timeIntervalSince1970)
        }
    }
    var pendingIncomingCount: Int {
        incomingRequests.filter { $0.status == .pending && activity($0.activityID)?.isActive(at: now) == true }.count
    }

    func conversations() -> [Conversation] {
        snapshot.conversations.sorted { (lastMessage(in: $0)?.sentAt ?? $0.createdAt) > (lastMessage(in: $1)?.sentAt ?? $1.createdAt) }
    }
    func messages(in conversation: Conversation) -> [Message] {
        snapshot.messages.filter { $0.conversationID == conversation.id }
    }
    func lastMessage(in conversation: Conversation) -> Message? { messages(in: conversation).last }
    func conversation(id: ID) -> Conversation? { snapshot.conversations.first { $0.id == id } }
    func otherParticipant(in conversation: Conversation) -> User? {
        conversation.participantIDs.first { $0 != me.id }.flatMap(user)
    }
    func conversation(for activityID: ID, with userID: ID) -> Conversation? {
        snapshot.conversations.first { $0.activityID == activityID && $0.participantIDs.contains(userID) }
    }
    /// Messaging only works while the guest's request is accepted and the plan is live.
    func isOpen(_ conversation: Conversation) -> Bool {
        guard let a = activity(conversation.activityID), !a.isCancelled else { return false }
        guard let guest = conversation.participantIDs.first(where: { $0 != a.hostID }) else { return false }
        return snapshot.requests.contains { $0.activityID == a.id && $0.requesterID == guest && $0.status == .accepted }
    }

    // MARK: Clock

    func tick() { now = .now }

    // MARK: Toasts

    func showToast(_ text: String, symbol: String = "checkmark.circle") {
        toastTask?.cancel()
        let t = Toast(text: text, symbol: symbol)
        alongWithAnimation(.alongQuick) { toast = t }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }
    func dismissToast() { alongWithAnimation(.alongQuick) { toast = nil } }

    // MARK: Mutations

    /// Runs a backend call, adopts the returned snapshot and reports failures as a toast.
    @discardableResult
    private func apply(_ work: () async throws -> AlongSnapshot) async -> Bool {
        do {
            let next = try await work()
            alongWithAnimation { snapshot = next }
            return true
        } catch {
            Haptics.light()
            showToast(error.localizedDescription, symbol: "exclamationmark.circle")
            return false
        }
    }

    func requestToJoin(_ activity: Activity) async {
        guard await apply({ try await backend.requestToJoin(activityID: activity.id) }) else { return }
        Haptics.success()
        showToast("Request sent to \(host(of: activity)?.firstName ?? "host")")
        if settings.demoHostsRespond { scheduleDemoResponse(for: activity.id) }
    }

    func withdrawRequest(_ activity: Activity) async {
        if await apply({ try await backend.withdrawRequest(activityID: activity.id) }) {
            Haptics.light()
            showToast("Request cancelled", symbol: "xmark.circle")
        }
    }

    func respond(to request: JoinRequest, accept: Bool) async {
        let name = user(request.requesterID)?.firstName ?? "Guest"
        if await apply({ try await backend.respond(requestID: request.id, accept: accept) }) {
            accept ? Haptics.success() : Haptics.light()
            showToast(accept ? "\(name) is in. Chat opened." : "Request declined", symbol: accept ? "checkmark.circle" : "xmark.circle")
        }
    }

    func leave(_ activity: Activity) async {
        if await apply({ try await backend.leave(activityID: activity.id) }) {
            Haptics.light()
            showToast("You left the plan", symbol: "arrow.uturn.left.circle")
        }
    }

    func cancel(_ activity: Activity) async {
        if await apply({ try await backend.cancelActivity(id: activity.id) }) {
            Haptics.light()
            showToast("Plan cancelled", symbol: "xmark.circle")
        }
    }

    @discardableResult
    func create(_ draft: ActivityDraft) async -> Bool {
        let ok = await apply { try await backend.createActivity(draft) }
        if ok {
            Haptics.success()
            showToast(draft.visibility == .public ? "Published. It's on the map." : "Saved to your plans")
        }
        return ok
    }

    func send(_ text: String, in conversation: Conversation) async {
        guard await apply({ try await backend.sendMessage(conversationID: conversation.id, text: text) }) else { return }
        if settings.demoHostsRespond {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.2))
                guard let self else { return }
                let next = await self.backend.simulateReply(conversationID: conversation.id)
                alongWithAnimation { self.snapshot = next }
            }
        }
    }

    func block(_ userID: ID) async {
        let name = user(userID)?.firstName ?? "User"
        let next = await backend.block(userID: userID)
        alongWithAnimation { snapshot = next }
        Haptics.light()
        showToast("\(name) blocked", symbol: "nosign")
    }

    func unblock(_ userID: ID) async {
        let next = await backend.unblock(userID: userID)
        alongWithAnimation { snapshot = next }
        showToast("Unblocked")
    }

    func report(_ target: ReportTarget, reason: ReportReason) async {
        await backend.report(target, reason: reason)
        Haptics.light()
        showToast("Thanks. We'll take a look.", symbol: "flag")
    }

    func updateProfile(_ user: User, silent: Bool = false) async {
        let next = await backend.updateProfile(user)
        alongWithAnimation { snapshot = next }
        if !silent { showToast("Profile saved") }
    }

    func updateSettings(_ change: (inout UserSettings) -> Void) async {
        var s = settings
        change(&s)
        snapshot.settings = s
        snapshot = await backend.updateSettings(s)
    }

    func resetDemo() async {
        let next = await backend.resetDemo()
        alongWithAnimation { snapshot = next }
        showToast("Demo data reset", symbol: "arrow.counterclockwise")
    }

    // MARK: Demo

    private func scheduleDemoResponse(for activityID: ID) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard let self else { return }
            let before = self.myRequest(for: activityID)?.status
            guard before == .pending else { return }
            let next = await self.backend.simulateHostResponse(activityID: activityID)
            alongWithAnimation { self.snapshot = next }
            if self.myRequest(for: activityID)?.status == .accepted, let a = self.activity(activityID) {
                Haptics.success()
                self.showToast("\(self.host(of: a)?.firstName ?? "Host") accepted your request", symbol: "person.crop.circle.badge.checkmark")
            }
        }
    }
}
