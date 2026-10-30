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

enum LoadState: Equatable {
    case idle, loading, loaded
    case failed(String)
}

/// Single source of truth for UI state. It mirrors the latest `AlongSnapshot` (my plans, requests, chats), a
/// map-bounded page of public discovery results, and exposes derived queries. Every mutation goes through the
/// backend; failures become short friendly toasts (never raw errors).
@MainActor @Observable
final class AppStore {
    private let backend: any AlongBackend
    private let realtime: (any RealtimeService)?
    let avatars: AvatarLoader

    private(set) var snapshot: AlongSnapshot
    /// Advances every 30 s so expired plans fall off the map without a relaunch.
    private(set) var now: Date = .now
    private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?

    // Discovery (public plans in the visible map area)
    private(set) var discovered: [Activity] = []
    private(set) var discoveryState: LoadState = .idle
    private(set) var hasMoreDiscovery = false
    private var hostCache: [ID: User] = [:]
    private var lastQuery: DiscoveryQuery?
    private var discoveryToken = 0

    // Refresh / realtime
    private(set) var isRefreshing = false
    private var refreshAgain = false
    private var refreshTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var realtimeUserID: ID?

    // Chat history paging
    private(set) var historyExhausted: Set<ID> = []

    /// Called when the server says the session is no longer valid.
    var onSessionExpired: (() -> Void)?

    init(backend: any AlongBackend, snapshot: AlongSnapshot, realtime: (any RealtimeService)? = nil) {
        self.backend = backend
        self.realtime = realtime
        self.snapshot = snapshot
        self.avatars = AvatarLoader { path in try await backend.avatarURL(path: path) }
    }

    static func bootstrap(backend: any AlongBackend = MockAlongBackend(), realtime: (any RealtimeService)? = nil) async throws -> AppStore {
        AppStore(backend: backend, snapshot: try await backend.loadSnapshot(), realtime: realtime)
    }

    var isDemo: Bool { backend is DemoService }
    var supportsAvatars: Bool { backend.supportsAvatars }

    // MARK: Lookups

    var me: User { snapshot.me }
    var settings: UserSettings { snapshot.settings }
    var blockedUsers: [User] { snapshot.users.filter { snapshot.blockedUserIDs.contains($0.id) } }

    func user(_ id: ID) -> User? {
        id == me.id ? me : snapshot.users.first { $0.id == id } ?? hostCache[id]
    }
    /// My own copy (exact locations, meeting details) wins over the public discovery copy.
    func activity(_ id: ID) -> Activity? {
        snapshot.activities.first { $0.id == id } ?? discovered.first { $0.id == id }
    }
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
    /// The most recent request I made for this plan (history rows exist after cancel / re-request).
    func myRequest(for activityID: ID) -> JoinRequest? {
        snapshot.requests.filter { $0.activityID == activityID && $0.requesterID == me.id }
            .max { $0.createdAt < $1.createdAt }
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
        discovered.filter { $0.visibility == .public && $0.isActive(at: now) && !isBlocked($0.hostID) }
    }

    /// Replaces the discovery list with the first page for `query` (map moved or a filter changed).
    func discover(_ query: DiscoveryQuery) async {
        var q = query
        q.offset = 0
        lastQuery = q
        discoveryToken += 1
        let token = discoveryToken
        discoveryState = .loading
        do {
            let page = try await backend.discover(q)
            guard token == discoveryToken else { return }          // a newer query superseded this one
            alongWithAnimation { discovered = page.activities }
            merge(hosts: page.hosts)
            hasMoreDiscovery = page.hasMore
            discoveryState = .loaded
        } catch {
            guard token == discoveryToken, ErrorPresenter.map(error) != .cancelled else { return }
            discoveryState = .failed(ErrorPresenter.message(for: error, fallback: "Couldn't load plans. Try again."))
            noteSessionExpiry(error)
        }
    }

    func loadMoreDiscovery() async {
        guard hasMoreDiscovery, discoveryState == .loaded, var q = lastQuery else { return }
        q.offset = discovered.count
        let token = discoveryToken
        do {
            let page = try await backend.discover(q)
            guard token == discoveryToken else { return }
            let known = Set(discovered.map(\.id))
            discovered += page.activities.filter { !known.contains($0.id) }
            merge(hosts: page.hosts)
            hasMoreDiscovery = page.hasMore
        } catch {
            noteSessionExpiry(error)                               // paging failures are quiet; the list stays usable
        }
    }

    func retryDiscovery() async { if let q = lastQuery { await discover(q) } }

    private func merge(hosts: [User]) {
        for h in hosts where hostCache[h.id] == nil || hostCache[h.id]?.bio.isEmpty == true { hostCache[h.id] = h }
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

    /// Requests other people have sent for live plans I host. Pending first, then newest.
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
        snapshot.messages.filter { $0.conversationID == conversation.id }.sorted { $0.sentAt < $1.sentAt }
    }
    func lastMessage(in conversation: Conversation) -> Message? { messages(in: conversation).last }
    func conversation(id: ID) -> Conversation? { snapshot.conversations.first { $0.id == id } }
    func otherParticipant(in conversation: Conversation) -> User? {
        conversation.participantIDs.first { $0 != me.id }.flatMap(user)
    }
    func conversation(for activityID: ID, with userID: ID) -> Conversation? {
        snapshot.conversations.first { $0.activityID == activityID && $0.participantIDs.contains(userID) }
    }
    /// Messaging only works while the guest's request is accepted and the plan isn't cancelled.
    func isOpen(_ conversation: Conversation) -> Bool {
        guard let a = activity(conversation.activityID), !a.isCancelled else { return false }
        guard let guest = conversation.participantIDs.first(where: { $0 != a.hostID }) else { return false }
        return snapshot.requests.contains { $0.activityID == a.id && $0.requesterID == guest && $0.status == .accepted }
    }
    func canLoadEarlier(_ conversation: Conversation) -> Bool { !historyExhausted.contains(conversation.id) }

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

    private func fail(_ error: Error, _ fallback: String) {
        let mapped = ErrorPresenter.map(error)
        guard mapped != .cancelled else { return }
        Haptics.light()
        showToast(ErrorPresenter.message(for: error, fallback: fallback), symbol: mapped == .offline ? "wifi.slash" : "exclamationmark.circle")
        noteSessionExpiry(error)
    }

    private func noteSessionExpiry(_ error: Error) {
        if ErrorPresenter.isSessionExpired(error) { onSessionExpired?() }
    }

    // MARK: Mutations

    /// Runs a backend call that returns a new snapshot, adopts it, refreshes discovery, and reports failure.
    @discardableResult
    private func apply(failure: String, _ work: () async throws -> AlongSnapshot) async -> Bool {
        do {
            let next = try await work()
            alongWithAnimation { snapshot = next }
            await rediscover()
            return true
        } catch {
            fail(error, failure)
            return false
        }
    }

    private func rediscover() async {
        guard let q = lastQuery else { return }
        let token = discoveryToken
        if let page = try? await backend.discover(q), token == discoveryToken {
            alongWithAnimation { discovered = page.activities }
            merge(hosts: page.hosts)
            hasMoreDiscovery = page.hasMore
            discoveryState = .loaded
        }
    }

    func requestToJoin(_ activity: Activity) async {
        guard await apply(failure: "Your request couldn't be sent.", { try await backend.requestToJoin(activityID: activity.id) }) else {
            await refresh(silent: true)                           // e.g. it filled up while the sheet was open
            return
        }
        Haptics.success()
        showToast("Request sent to \(host(of: activity)?.firstName ?? "host")")
        scheduleDemoResponse(for: activity.id)
    }

    func withdrawRequest(_ activity: Activity) async {
        if await apply(failure: "Couldn't cancel your request.", { try await backend.withdrawRequest(activityID: activity.id) }) {
            Haptics.light()
            showToast("Request cancelled", symbol: "xmark.circle")
        }
    }

    func respond(to request: JoinRequest, accept: Bool) async {
        let name = user(request.requesterID)?.firstName ?? "Guest"
        if await apply(failure: "Couldn't update that request.", { try await backend.respond(requestID: request.id, accept: accept) }) {
            accept ? Haptics.success() : Haptics.light()
            showToast(accept ? "\(name) is in. Chat opened." : "Request declined", symbol: accept ? "checkmark.circle" : "xmark.circle")
        } else {
            await refresh(silent: true)
        }
    }

    func leave(_ activity: Activity) async {
        if await apply(failure: "Couldn't leave the plan.", { try await backend.leave(activityID: activity.id) }) {
            Haptics.light()
            showToast("You left the plan", symbol: "arrow.uturn.left.circle")
        }
    }

    func cancel(_ activity: Activity) async {
        if await apply(failure: "Couldn't cancel the plan.", { try await backend.cancelActivity(id: activity.id) }) {
            Haptics.light()
            showToast("Plan cancelled", symbol: "xmark.circle")
        }
    }

    @discardableResult
    func create(_ draft: ActivityDraft) async -> Bool {
        let failure = draft.details.isWalk ? "Couldn't publish your walk. Try again." : "Couldn't publish your session. Try again."
        let ok = await apply(failure: failure) { try await backend.createActivity(draft) }
        if ok {
            Haptics.success()
            showToast(draft.visibility == .public ? "Published. It's on the map." : "Saved to your plans")
        }
        return ok
    }

    @discardableResult
    func edit(_ edit: ActivityEdit) async -> Bool {
        let ok = await apply(failure: "Couldn't save your changes.") { try await backend.updateActivity(edit) }
        if ok { Haptics.success(); showToast("Changes saved") }
        return ok
    }

    // MARK: Messaging

    /// Optimistic: the bubble appears immediately and is rolled back (returning `false`) if the server refuses it.
    @discardableResult
    func send(_ text: String, in conversation: Conversation) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let temp = Message(id: "local-\(UUID().uuidString)", conversationID: conversation.id, senderID: me.id, text: trimmed, sentAt: .now)
        snapshot.messages.append(temp)
        do {
            let stored = try await backend.sendMessage(conversationID: conversation.id, text: trimmed)
            snapshot.messages.removeAll { $0.id == temp.id }
            if !snapshot.messages.contains(where: { $0.id == stored.id }) { snapshot.messages.append(stored) }
            scheduleDemoReply(in: conversation)
            return true
        } catch {
            snapshot.messages.removeAll { $0.id == temp.id }
            fail(error, "Message not sent.")
            if ErrorPresenter.map(error) == .chatClosed { await refresh(silent: true) }
            return false
        }
    }

    /// Loads the newest page when a chat opens, or the page before the oldest message we hold.
    func loadHistory(for conversation: Conversation, older: Bool) async {
        let pageSize = 30
        let oldest = older ? messages(in: conversation).first(where: { !$0.id.hasPrefix("local-") })?.sentAt : nil
        do {
            let page = try await backend.loadMessages(conversationID: conversation.id, before: oldest, limit: pageSize)
            let known = Set(snapshot.messages.map(\.id))
            snapshot.messages += page.filter { !known.contains($0.id) }
            if page.count < pageSize { historyExhausted.insert(conversation.id) }
        } catch {
            if older { fail(error, "Couldn't load earlier messages.") }
        }
    }

    // MARK: Safety

    func block(_ userID: ID) async {
        let name = user(userID)?.firstName ?? "User"
        do {
            let next = try await backend.block(userID: userID)
            alongWithAnimation { snapshot = next }
            await rediscover()
            Haptics.light()
            showToast("\(name) blocked", symbol: "nosign")
        } catch { fail(error, "Couldn't block \(name). Try again.") }
    }

    func unblock(_ userID: ID) async {
        do {
            let next = try await backend.unblock(userID: userID)
            alongWithAnimation { snapshot = next }
            await rediscover()
            showToast("Unblocked")
        } catch { fail(error, "Couldn't unblock. Try again.") }
    }

    func report(_ target: ReportTarget, reason: ReportReason) async {
        do {
            try await backend.report(target, reason: reason)
            Haptics.light()
            showToast("Thanks. We'll take a look.", symbol: "flag")
        } catch { fail(error, "Couldn't send your report. Try again.") }
    }

    // MARK: Profile & settings

    func updateProfile(_ user: User, silent: Bool = false) async {
        let previous = snapshot.me
        snapshot.me = user                                          // optimistic; rolled back on failure
        do {
            snapshot.me = try await backend.updateProfile(user)
            if !silent { showToast("Profile saved") }
        } catch {
            snapshot.me = previous
            fail(error, "Couldn't save your profile.")
        }
    }

    /// Uploads a new profile photo (already resized JPEG) and points the profile at it.
    func setAvatar(jpeg: Data) async -> Bool {
        let old = me.avatarPath
        do {
            let path = try await backend.uploadAvatar(jpeg)
            var u = me
            u.avatarPath = path
            snapshot.me = try await backend.updateProfile(u)
            if let old { avatars.invalidate(old); try? await backend.deleteAvatar(path: old) }
            showToast("Photo updated")
            return true
        } catch {
            fail(error, "Couldn't upload your photo. Try again.")
            return false
        }
    }

    func removeAvatar() async {
        guard let old = me.avatarPath else { return }
        var u = me
        u.avatarPath = nil
        do {
            snapshot.me = try await backend.updateProfile(u)
            avatars.invalidate(old)
            try? await backend.deleteAvatar(path: old)
        } catch { fail(error, "Couldn't remove your photo.") }
    }

    func updateSettings(_ change: (inout UserSettings) -> Void) async {
        let previous = settings
        var s = settings
        change(&s)
        snapshot.settings = s
        do { try await backend.updateSettings(s) } catch {
            snapshot.settings = previous
            fail(error, "Couldn't save that setting.")
        }
    }

    /// Removes the avatar object (SQL can't delete Storage files) before the account row is deleted server-side.
    func prepareForAccountDeletion() async {
        await stopRealtime()
        if let path = me.avatarPath { try? await backend.deleteAvatar(path: path) }
    }

    // MARK: Refresh & realtime

    /// Pull-to-refresh and reconnect path. `silent` suppresses error toasts for background refreshes.
    func refresh(announce: Bool = false, silent: Bool = false) async {
        if isRefreshing { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            let before = announce ? signature() : nil
            do {
                let next = try await backend.loadSnapshot()
                alongWithAnimation { snapshot = next }
                await rediscover()
                if let before { announceChanges(since: before) }
            } catch {
                if !silent { fail(error, "Couldn't refresh. Pull to try again.") } else { noteSessionExpiry(error) }
            }
        } while refreshAgain
    }

    private struct Signature {
        var pendingIncoming: Set<ID>
        var myRequests: [ID: RequestStatus]
    }
    private func signature() -> Signature {
        Signature(pendingIncoming: Set(snapshot.requests.filter { $0.status == .pending && $0.requesterID != me.id }.map(\.id)),
                  myRequests: Dictionary(snapshot.requests.filter { $0.requesterID == me.id }.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a }))
    }
    /// Subtle toasts for things that happened while the user wasn't looking.
    private func announceChanges(since old: Signature) {
        let new = signature()
        if let fresh = snapshot.requests.first(where: { new.pendingIncoming.contains($0.id) && !old.pendingIncoming.contains($0.id) }) {
            let name = user(fresh.requesterID)?.firstName ?? "Someone"
            showToast("\(name) wants to join your plan", symbol: "person.crop.circle.badge.plus")
            return
        }
        for (id, status) in new.myRequests where old.myRequests[id] == .pending && status != .pending {
            guard let r = snapshot.requests.first(where: { $0.id == id }), let a = activity(r.activityID) else { continue }
            let hostName = host(of: a)?.firstName ?? "The host"
            if status == .accepted { showToast("\(hostName) accepted your request", symbol: "person.crop.circle.badge.checkmark") }
            else if status == .declined { showToast("\(hostName) can't fit you in this time", symbol: "xmark.circle") }
            return
        }
    }

    func startRealtime() async {
        guard let realtime, realtimeTask == nil else { return }      // never double-subscribe
        let uid = me.id
        realtimeUserID = uid
        let stream = await realtime.start(userID: uid)
        realtimeTask = Task { [weak self] in
            for await event in stream { self?.handle(event) }
        }
    }

    func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        refreshTask?.cancel()
        await realtime?.stop()
    }

    /// Foreground/background lifecycle: sockets are released in the background and rebuilt on return.
    func scenePhaseChanged(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            tick()
            if realtime != nil, realtimeTask == nil { await startRealtime(); await refresh(announce: true, silent: true) }
        case .background:
            await stopRealtime()
        default: break
        }
    }

    private func handle(_ event: RealtimeEvent) {
        switch event {
        case .message(let m):
            guard snapshot.conversations.contains(where: { $0.id == m.conversationID }) else { scheduleRefresh(); return }
            if !snapshot.messages.contains(where: { $0.id == m.id }) {
                // Our own optimistic bubble is replaced by the stored row; avoid showing both.
                if m.senderID == me.id, let i = snapshot.messages.firstIndex(where: { $0.id.hasPrefix("local-") && $0.text == m.text }) {
                    snapshot.messages.remove(at: i)
                }
                alongWithAnimation { snapshot.messages.append(m) }
            }
        case .requestsChanged, .activityChanged, .conversationsChanged, .reconnected:
            scheduleRefresh()
        }
    }

    /// Coalesces bursts of realtime events into a single refresh.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.refresh(announce: true, silent: true)
        }
    }

    // MARK: Demo mode only

    func resetDemo() async {
        guard let demo = backend as? DemoService else { return }
        let next = await demo.resetDemo()
        alongWithAnimation { snapshot = next }
        await rediscover()
        showToast("Demo data reset", symbol: "arrow.counterclockwise")
    }

    private func scheduleDemoResponse(for activityID: ID) {
        guard settings.demoHostsRespond, let demo = backend as? DemoService else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard let self, self.myRequest(for: activityID)?.status == .pending else { return }
            let next = await demo.simulateHostResponse(activityID: activityID)
            alongWithAnimation { self.snapshot = next }
            if self.myRequest(for: activityID)?.status == .accepted, let a = self.activity(activityID) {
                Haptics.success()
                self.showToast("\(self.host(of: a)?.firstName ?? "Host") accepted your request", symbol: "person.crop.circle.badge.checkmark")
            }
        }
    }

    private func scheduleDemoReply(in conversation: Conversation) {
        guard settings.demoHostsRespond, let demo = backend as? DemoService else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self else { return }
            let next = await demo.simulateReply(conversationID: conversation.id)
            alongWithAnimation { self.snapshot = next }
        }
    }
}

extension ActivityDetails {
    var isWalk: Bool { if case .walk = self { true } else { false } }
}
