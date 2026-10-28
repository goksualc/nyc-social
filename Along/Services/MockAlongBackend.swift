import Foundation

/// In-memory stand-in for the real backend.
///
/// Everything in here is *simulated*. The rules (spot limits, blocking, redaction, chat gating) are
/// enforced here so the UI can stay thin — but in production each one must be enforced on the server
/// (Postgres RLS policies / edge functions), never trusted to the client. See `SafetyPolicy`.
actor MockAlongBackend: AlongBackend {
    private var db: MockDatabase
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { .now }) {
        self.clock = clock
        self.db = SeedData.make(now: clock())
    }

    private var me: ID { db.meID }

    // MARK: Snapshot

    /// What the signed-in user may see. Mirrors what RLS + a view layer would return.
    private func snapshot() -> AlongSnapshot {
        let visibleActivities: [Activity] = db.activities.compactMap { activity in
            let isMember = activity.hostID == me || activity.participantIDs.contains(me)
            if db.blocked.contains(activity.hostID) { return nil }
            if activity.visibility == .private && !isMember { return nil }
            return redacted(activity, isMember: isMember)
        }
        let visibleIDs = Set(visibleActivities.map(\.id))
        let requests = db.requests.filter {
            visibleIDs.contains($0.activityID) && !db.blocked.contains($0.requesterID)
        }
        let conversations = db.conversations.filter { c in
            visibleIDs.contains(c.activityID) && !c.participantIDs.contains { db.blocked.contains($0) }
        }
        let convIDs = Set(conversations.map(\.id))
        return AlongSnapshot(
            me: db.users.first { $0.id == me }!,
            settings: db.settings,
            users: db.users,
            activities: visibleActivities.sorted { $0.startDate < $1.startDate },
            requests: requests,
            conversations: conversations,
            messages: db.messages.filter { convIDs.contains($0.conversationID) }.sorted { $0.sentAt < $1.sentAt },
            blockedUserIDs: db.blocked)
    }

    /// Exact places and meeting instructions only leave the server for the host and accepted guests.
    private func redacted(_ activity: Activity, isMember: Bool) -> Activity {
        var a = activity
        a.hasPreciseAccess = isMember
        guard !isMember else { return a }
        a.meetingDetails = ""
        switch a.details {
        case .walk(var w):
            w.from = w.from.redacted(); w.to = w.to.redacted()
            a.details = .walk(w)
        case .cowork(var c):
            c.venue = c.venue.redacted()
            a.details = .cowork(c)
        }
        return a
    }

    private func index(ofActivity id: ID) throws -> Int {
        guard let i = db.activities.firstIndex(where: { $0.id == id }), !db.blocked.contains(db.activities[i].hostID) else {
            throw AlongError.notFound
        }
        return i
    }

    // MARK: Auth

    func signInDemo() async -> AlongSnapshot { snapshot() }

    // MARK: Activities

    func loadSnapshot() async -> AlongSnapshot { snapshot() }

    func createActivity(_ draft: ActivityDraft) async throws -> AlongSnapshot {
        let now = clock()
        guard draft.startDate > now.addingTimeInterval(-60) else { throw AlongError.startInPast }
        guard draft.endDate > draft.startDate else { throw AlongError.invalidTimes }
        switch draft.details {
        case .walk(let w):
            guard ManhattanGeo.contains(w.from.coordinate), ManhattanGeo.contains(w.to.coordinate) else { throw AlongError.outsideManhattan }
            guard w.from.coordinate.distance(to: w.to.coordinate) > 50 else { throw AlongError.sameLocation }
        case .cowork(let c):
            guard ManhattanGeo.contains(c.venue.coordinate) else { throw AlongError.outsideManhattan }
        }
        let activity = Activity(
            id: UUID().uuidString, title: draft.title, hostID: me, details: draft.details,
            startDate: draft.startDate, endDate: draft.endDate, visibility: draft.visibility,
            capacity: min(max(draft.capacity, 1), 5), note: draft.note, meetingDetails: draft.meetingDetails, createdAt: now)
        db.activities.append(activity)
        return snapshot()
    }

    func cancelActivity(id: ID) async throws -> AlongSnapshot {
        let i = try index(ofActivity: id)
        guard db.activities[i].hostID == me else { throw AlongError.notAllowed }
        db.activities[i].isCancelled = true
        for r in db.requests.indices where db.requests[r].activityID == id && db.requests[r].status == .pending {
            db.requests[r].status = .declined
        }
        return snapshot()
    }

    // MARK: Requests

    func requestToJoin(activityID: ID) async throws -> AlongSnapshot {
        let i = try index(ofActivity: activityID)
        let a = db.activities[i]
        guard a.hostID != me, a.visibility == .public else { throw AlongError.notAllowed }
        guard a.isActive(at: clock()) else { throw AlongError.notFound }
        guard !a.isFull else { throw AlongError.activityFull }
        if let r = db.requests.firstIndex(where: { $0.activityID == activityID && $0.requesterID == me }) {
            guard db.requests[r].status == .withdrawn else { throw AlongError.alreadyRequested }
            db.requests[r].status = .pending
            db.requests[r].createdAt = clock()
        } else {
            db.requests.append(JoinRequest(id: UUID().uuidString, activityID: activityID, requesterID: me, createdAt: clock()))
        }
        return snapshot()
    }

    func withdrawRequest(activityID: ID) async throws -> AlongSnapshot {
        guard let r = db.requests.firstIndex(where: { $0.activityID == activityID && $0.requesterID == me && $0.status == .pending }) else {
            throw AlongError.notFound
        }
        db.requests[r].status = .withdrawn
        return snapshot()
    }

    func respond(requestID: ID, accept: Bool) async throws -> AlongSnapshot {
        guard let r = db.requests.firstIndex(where: { $0.id == requestID }),
              db.requests[r].status == .pending,
              !db.blocked.contains(db.requests[r].requesterID) else { throw AlongError.notFound }
        let i = try index(ofActivity: db.requests[r].activityID)
        guard db.activities[i].hostID == me else { throw AlongError.notAllowed }
        guard db.activities[i].isActive(at: clock()) else { throw AlongError.notFound }
        if accept {
            guard !db.activities[i].isFull else { throw AlongError.activityFull }
            acceptRequest(at: r, activityIndex: i, welcome: nil)
        } else {
            db.requests[r].status = .declined
        }
        return snapshot()
    }

    /// Shared by host acceptance and the demo "host responds" helper.
    private func acceptRequest(at r: Int, activityIndex i: Int, welcome: (sender: ID, text: String)?) {
        let requester = db.requests[r].requesterID
        db.requests[r].status = .accepted
        if !db.activities[i].participantIDs.contains(requester) { db.activities[i].participantIDs.append(requester) }
        let host = db.activities[i].hostID
        let activityID = db.activities[i].id
        let convID: ID
        if let c = db.conversations.first(where: { $0.activityID == activityID && Set($0.participantIDs) == [host, requester] }) {
            convID = c.id
        } else {
            convID = UUID().uuidString
            db.conversations.append(Conversation(id: convID, activityID: activityID, participantIDs: [host, requester], createdAt: clock()))
        }
        let opener = welcome ?? (requester, requester == me ? "Thanks for having me along." : "Thanks for letting me join. Where should I look for you?")
        db.messages.append(Message(id: UUID().uuidString, conversationID: convID, senderID: opener.sender, text: opener.text, sentAt: clock()))
    }

    func leave(activityID: ID) async throws -> AlongSnapshot {
        let i = try index(ofActivity: activityID)
        guard let r = db.requests.firstIndex(where: { $0.activityID == activityID && $0.requesterID == me && $0.status == .accepted }) else {
            throw AlongError.notAllowed
        }
        db.requests[r].status = .withdrawn
        db.activities[i].participantIDs.removeAll { $0 == me }
        return snapshot()
    }

    // MARK: Messaging

    func sendMessage(conversationID: ID, text: String) async throws -> AlongSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshot() }
        guard let c = db.conversations.first(where: { $0.id == conversationID }), c.participantIDs.contains(me) else { throw AlongError.notFound }
        guard isChatOpen(c) else { throw AlongError.chatClosed }
        db.messages.append(Message(id: UUID().uuidString, conversationID: conversationID, senderID: me, text: trimmed, sentAt: clock()))
        return snapshot()
    }

    /// A conversation is only usable while the guest's request is accepted and the plan is still live.
    private func isChatOpen(_ c: Conversation) -> Bool {
        guard let a = db.activities.first(where: { $0.id == c.activityID }), !a.isCancelled else { return false }
        if c.participantIDs.contains(where: { db.blocked.contains($0) }) { return false }
        let guest = c.participantIDs.first { $0 != a.hostID }
        return db.requests.contains { $0.activityID == a.id && $0.requesterID == guest && $0.status == .accepted }
    }

    // MARK: Profile

    func updateProfile(_ user: User) async -> AlongSnapshot {
        if let i = db.users.firstIndex(where: { $0.id == me }) {
            var u = user
            u.id = me
            u.firstName = String(user.firstName.trimmingCharacters(in: .whitespaces).prefix(24))
            if u.firstName.isEmpty { u.firstName = db.users[i].firstName }
            db.users[i] = u
        }
        return snapshot()
    }

    func updateSettings(_ settings: UserSettings) async -> AlongSnapshot {
        db.settings = settings
        return snapshot()
    }

    // MARK: Safety

    func block(userID: ID) async -> AlongSnapshot {
        guard userID != me else { return snapshot() }
        db.blocked.insert(userID)
        // Sever every live relationship between the two people.
        for r in db.requests.indices {
            let activity = db.activities.first { $0.id == db.requests[r].activityID }
            let involvesThem = db.requests[r].requesterID == userID || activity?.hostID == userID
            let involvesMe = db.requests[r].requesterID == me || activity?.hostID == me
            if involvesThem && involvesMe && [.pending, .accepted].contains(db.requests[r].status) {
                db.requests[r].status = .withdrawn
            }
        }
        for a in db.activities.indices {
            if db.activities[a].hostID == userID { db.activities[a].participantIDs.removeAll { $0 == me } }
            if db.activities[a].hostID == me { db.activities[a].participantIDs.removeAll { $0 == userID } }
        }
        return snapshot()
    }

    func unblock(userID: ID) async -> AlongSnapshot {
        db.blocked.remove(userID)
        return snapshot()
    }

    func report(_ target: ReportTarget, reason: ReportReason) async {
        switch target {
        case .user(let id): db.reports.append("user:\(id):\(reason.rawValue)")
        case .activity(let id): db.reports.append("activity:\(id):\(reason.rawValue)")
        }
    }

    // MARK: Demo helpers

    func simulateHostResponse(activityID: ID) async -> AlongSnapshot {
        guard let i = db.activities.firstIndex(where: { $0.id == activityID }),
              let r = db.requests.firstIndex(where: { $0.activityID == activityID && $0.requesterID == me && $0.status == .pending }),
              !db.blocked.contains(db.activities[i].hostID),
              db.activities[i].isActive(at: clock()) else { return snapshot() }
        if db.activities[i].isFull {
            db.requests[r].status = .declined
        } else {
            let host = db.activities[i].hostID
            let first = db.users.first { $0.id == host }?.firstName ?? "Your host"
            acceptRequest(at: r, activityIndex: i, welcome: (host, "Hi, it's \(first). Glad you can join — check the plan for where to meet."))
        }
        return snapshot()
    }

    func simulateReply(conversationID: ID) async -> AlongSnapshot {
        guard let c = db.conversations.first(where: { $0.id == conversationID }), isChatOpen(c),
              let other = c.participantIDs.first(where: { $0 != me }) else { return snapshot() }
        let replies = ["Sounds good!", "Great, see you there.", "Perfect. I'll message if I'm running late.", "Thanks for the heads-up."]
        let count = db.messages.filter { $0.conversationID == conversationID && $0.senderID == other }.count
        db.messages.append(Message(id: UUID().uuidString, conversationID: conversationID, senderID: other,
                                   text: replies[count % replies.count], sentAt: clock()))
        return snapshot()
    }

    func resetDemo() async -> AlongSnapshot {
        db = SeedData.make(now: clock())
        return snapshot()
    }
}
