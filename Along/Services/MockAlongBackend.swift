import Foundation
import CoreLocation

/// In-memory stand-in for the real backend.
///
/// Everything in here is *simulated*. The rules (spot limits, blocking, redaction, chat gating) are
/// enforced here so the UI can stay thin — but in production each one must be enforced on the server
/// (Postgres RLS policies / edge functions), never trusted to the client. See `SafetyPolicy`.
actor MockAlongBackend: AlongBackend, DemoService {
    private var db: MockDatabase
    fileprivate var walkSessions: [WalkSession] = []
    /// In-memory photo storage, used when avatars are switched on (tests). Demo mode keeps them off, like before.
    private var storedAvatars: [String: Data] = [:]
    let avatarsEnabled: Bool
    /// Test hooks: make the next steps of a photo change fail.
    private(set) var failAvatarUpload = false
    private(set) var failAvatarProfileUpdate = false
    func setFailAvatarUpload(_ on: Bool) { failAvatarUpload = on }
    func setFailAvatarProfileUpdate(_ on: Bool) { failAvatarProfileUpdate = on }
    var storedAvatarPaths: [String] { storedAvatars.keys.sorted() }
    fileprivate var memoryPrefs: [ID: (show: Bool, reveal: Bool)] = [:]
    fileprivate var reportedDistance: [ID: Int] = [:]
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { .now }, avatarsEnabled: Bool = false) {
        self.avatarsEnabled = avatarsEnabled
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
        if a.hostAnonymous, a.hostID != me { a.hostID = User.anonymousPrefix + a.id }       // same masking the server applies, members included
        guard !isMember else { return a }
        a.meetingDetails = ""
        a.walk.from = a.walk.from.redacted()
        a.walk.to = a.walk.to.redacted()
        return a
    }

    private func index(ofActivity id: ID) throws -> Int {
        guard let i = db.activities.firstIndex(where: { $0.id == id }), !db.blocked.contains(db.activities[i].hostID) else {
            throw AlongError.notFound
        }
        return i
    }

    // MARK: Activities

    func loadSnapshot() async throws -> AlongSnapshot { snapshot() }

    /// Same contract as the PostGIS `discover_activities` RPC: public, live, inside the box, overlapping the window.
    func discover(_ query: DiscoveryQuery) async throws -> DiscoveryPage {
        let now = clock()
        let from = max(now, query.from ?? now)
        func inBox(_ c: CLLocationCoordinate2D) -> Bool {
            (query.minLat...query.maxLat).contains(c.latitude) && (query.minLng...query.maxLng).contains(c.longitude)
        }
        let all = snapshot().activities
            .filter { a in
                guard a.visibility == .public, a.isActive(at: now), a.endDate > from else { return false }
                if let to = query.to, a.startDate >= to { return false }
                let (s, e) = a.routeEndpoints
                return inBox(s) || inBox(e)
            }
            .sorted { $0.startDate < $1.startDate }
        let page = Array(all.dropFirst(query.offset).prefix(query.limit))
        let hostIDs = Set(page.map(\.hostID))
        return DiscoveryPage(activities: page, hosts: db.users.filter { hostIDs.contains($0.id) }, hasMore: all.count > query.offset + page.count)
    }

    func nearby(to center: Coordinate, radiusMeters: Double, limit: Int) async throws -> DiscoveryPage {
        let now = clock()
        let found = snapshot().activities
            .filter { $0.visibility == .public && $0.isActive(at: now) }
            .filter { Coordinate($0.mapCoordinate).distance(to: center) <= radiusMeters }
            .sorted { Coordinate($0.mapCoordinate).distance(to: center) < Coordinate($1.mapCoordinate).distance(to: center) }
        let page = Array(found.prefix(limit))
        return DiscoveryPage(activities: page, hosts: [], hasMore: found.count > page.count)
    }

    func searchAlongRoute(_ q: RouteSearchQuery) async throws -> [RouteMatch] {
        guard q.route.count >= 2 else { throw AlongError.notFound }
        let now = clock()
        func dist(_ p: Coordinate) -> Double { q.route.map { p.distance(to: $0) }.min() ?? .infinity }
        func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
            let y = sin((b.longitude - a.longitude) * .pi / 180) * cos(b.latitude * .pi / 180)
            let x = cos(a.latitude * .pi / 180) * sin(b.latitude * .pi / 180) - sin(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * cos((b.longitude - a.longitude) * .pi / 180)
            return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }
        let routeBearing = bearing(q.route[0], q.route[q.route.count - 1])
        let snap = snapshot()
        var out: [RouteMatch] = []
        for a in snap.activities where a.visibility == .public && a.isActive(at: now) && a.endDate > (q.from ?? now) {
            if let to = q.to, a.startDate >= to { continue }
            let line = a.routeCoordinates.count >= 2 ? a.routeCoordinates : [a.walk.from.coordinate, a.walk.to.coordinate]
            // sample the walk every few points and count how much of it is inside the corridor
            let samples = stride(from: 0, to: line.count, by: max(1, line.count / 40)).map { line[$0] } + [line[line.count - 1]]
            let inside = Double(samples.filter { dist($0) <= q.corridorMeters }.count) / Double(samples.count)
            guard inside > 0 else { continue }
            let diff = abs(bearing(line[0], line[line.count - 1]) - routeBearing)
            let dir = diff > 180 ? 360 - diff : diff
            let sNear = dist(line[0]) <= q.corridorMeters, eNear = dist(line[line.count - 1]) <= q.corridorMeters
            let score = 0.5 * inside + 0.2 * (1 - dir / 180) + 0.15 * (sNear ? 1 : 0) + 0.15 * (eNear ? 1 : 0)
            let host = snap.users.first { $0.id == a.hostID } ?? User.anonymousHost(id: a.hostID, interests: a.hostInterests)
            out.append(RouteMatch(activity: a, host: host, overlap: inside, routeDistanceMeters: dist(line[0]), directionDiffDegrees: dir,
                                  startsNear: sNear, endsNear: eNear, score: score))
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(q.limit))
    }

    func updateActivity(_ edit: ActivityEdit) async throws -> AlongSnapshot {
        let i = try index(ofActivity: edit.activityID)
        guard db.activities[i].hostID == me else { throw AlongError.notAllowed }
        guard db.activities[i].isActive(at: clock()) else { throw AlongError.activityClosed }
        let start = edit.startDate ?? db.activities[i].startDate
        let end = edit.endDate ?? db.activities[i].endDate
        guard end > start else { throw AlongError.invalidTimes }
        if edit.startDate != nil, start < clock().addingTimeInterval(-120) { throw AlongError.startInPast }
        if let cap = edit.capacity {
            guard (1...5).contains(cap) else { throw AlongError.notAllowed }
            guard cap >= db.activities[i].participantIDs.count else { throw AlongError.capacityBelowAccepted }
            db.activities[i].capacity = cap
        }
        db.activities[i].startDate = start
        db.activities[i].endDate = end
        if let note = edit.note { db.activities[i].note = note }
        if let spot = edit.meetingDetails { db.activities[i].meetingDetails = spot }
        return snapshot()
    }

    func createActivity(_ draft: ActivityDraft) async throws -> AlongSnapshot {
        let now = clock()
        guard draft.startDate > now.addingTimeInterval(-60) else { throw AlongError.startInPast }
        guard draft.endDate > draft.startDate else { throw AlongError.invalidTimes }
        let w = draft.walk
        guard NYCGeo.contains(w.from.coordinate), NYCGeo.contains(w.to.coordinate) else { throw AlongError.outsideNYC }
        guard w.from.coordinate.distance(to: w.to.coordinate) > 50 else { throw AlongError.sameLocation }
        let activity = Activity(
            id: UUID().uuidString, title: draft.title, hostID: me, walk: draft.walk,
            startDate: draft.startDate, endDate: draft.endDate, visibility: .public,       // a walk is always on the map
            capacity: min(max(draft.capacity, 1), 5), note: draft.note, meetingDetails: draft.meetingDetails, createdAt: now,
            hostAnonymous: draft.anonymousHost, hostInterests: Array(draft.hostInterests.prefix(3)),
            mindPrompt: draft.mindPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(draft.mindPrompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)))
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
        let myID = me
        db.activities[i].participantIDs.removeAll { $0 == myID }
        return snapshot()
    }

    // MARK: Messaging

    func sendMessage(conversationID: ID, text: String) async throws -> Message {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AlongError.notAllowed }
        guard let c = db.conversations.first(where: { $0.id == conversationID }), c.participantIDs.contains(me) else { throw AlongError.notFound }
        guard isChatOpen(c) else { throw AlongError.chatClosed }
        let message = Message(id: UUID().uuidString, conversationID: conversationID, senderID: me, text: trimmed, sentAt: clock())
        db.messages.append(message)
        return message
    }

    func loadMessages(conversationID: ID, before: Date?, limit: Int) async throws -> [Message] {
        let all = db.messages.filter { $0.conversationID == conversationID && (before == nil || $0.sentAt < before!) }
            .sorted { $0.sentAt < $1.sentAt }
        return Array(all.suffix(limit))
    }

    /// A conversation is only usable while the guest's request is accepted and the plan is still live.
    private func isChatOpen(_ c: Conversation) -> Bool {
        guard let a = db.activities.first(where: { $0.id == c.activityID }), !a.isCancelled else { return false }
        if c.participantIDs.contains(where: { db.blocked.contains($0) }) { return false }
        let guest = c.participantIDs.first { $0 != a.hostID }
        return db.requests.contains { $0.activityID == a.id && $0.requesterID == guest && $0.status == .accepted }
    }

    // MARK: Profile

    func loadMyProfile() async throws -> MyProfile {
        MyProfile(user: db.users.first { $0.id == me }!, fullName: nil, hasDisplayName: true, ageConfirmed: true,
                  onboardingCompleted: !LaunchOptions.current.onboarding)
    }

    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws {
        if let i = db.users.firstIndex(where: { $0.id == me }) {
            db.users[i].firstName = draft.displayName
            db.users[i].bio = draft.bio
            db.users[i].hobbies = draft.hobbies
            db.users[i].instagram = draft.instagram
            db.users[i].xHandle = draft.xHandle
            db.users[i].pacePreference = draft.pacePreference
            db.users[i].preferredDuration = draft.preferredDuration
            db.users[i].favoriteNeighborhoods = draft.favoriteNeighborhoods
        }
    }

    func updateProfile(_ user: User) async throws -> User {
        guard let i = db.users.firstIndex(where: { $0.id == me }) else { throw AlongError.notFound }
        var u = user
        u.id = me
        u.firstName = String(user.firstName.trimmingCharacters(in: .whitespaces).prefix(24))
        if u.firstName.isEmpty { u.firstName = db.users[i].firstName }
        u.avatarPath = db.users[i].avatarPath       // the photo has its own write; a profile save never touches it
        db.users[i] = u
        return u
    }

    func updateSettings(_ settings: UserSettings) async throws { db.settings = settings }

    // Avatars need Storage, which only exists with a real backend.
    nonisolated var supportsAvatars: Bool { avatarsEnabled }
    func uploadAvatar(_ jpeg: Data) async throws -> String {
        guard avatarsEnabled, !failAvatarUpload else { throw AlongError.uploadFailed }
        guard jpeg.count <= 2_000_000 else { throw AlongError.imageTooLarge }
        let path = AvatarStoragePath.make(userID: db.meID, now: clock())
        storedAvatars[path] = jpeg
        return path
    }
    func deleteAvatar(path: String) async throws { storedAvatars[path] = nil }
    func avatarURL(path: String) async throws -> URL {
        guard avatarsEnabled, storedAvatars[path] != nil else { throw AlongError.notFound }
        return URL(string: "https://example.invalid/\(path)")!
    }
    func updateAvatarPath(_ path: String?) async throws {
        guard !failAvatarProfileUpdate else { throw AlongError.generic }
        guard let i = db.users.firstIndex(where: { $0.id == me }) else { throw AlongError.notFound }
        db.users[i].avatarPath = path
    }

    // MARK: Safety

    func block(userID: ID) async throws -> AlongSnapshot {
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

    func unblock(userID: ID) async throws -> AlongSnapshot {
        db.blocked.remove(userID)
        return snapshot()
    }

    func report(_ target: ReportTarget, reason: ReportReason) async throws {
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

// MARK: - Walk sessions (demo only)
//
// The demo has no second person, so the *partner* is simulated: they press "I'm ready" and "finish" the moment you do.
// There is never any fake location data — in demo mode the partner's marker simply reports "location unavailable".

extension MockAlongBackend {
    private func parties(of activityID: ID) throws -> (host: User, guest: User) {
        guard let a = db.activities.first(where: { $0.id == activityID }), a.isActive(at: clock()) else { throw AlongError.activityClosed }
        let guests = db.requests.filter { $0.activityID == activityID && $0.status == .accepted }.map(\.requesterID)
        // Same order as the server: who you are first, then how many people are in.
        guard a.hostID == db.meID || guests.contains(db.meID) else { throw AlongError.notAllowed }
        guard !guests.isEmpty else { throw AlongError.noParticipant }
        guard guests.count == 1 else { throw AlongError.sessionRequiresTwo }
        guard let host = db.users.first(where: { $0.id == a.hostID }), let guest = db.users.first(where: { $0.id == guests[0] }) else { throw AlongError.notFound }
        return (host, guest)
    }

    private func participant(_ u: User, role: String, joined: Bool) -> WalkSessionParticipant {
        WalkSessionParticipant(userId: u.id, role: role, displayName: u.firstName, avatarPath: u.avatarPath, joinedAt: joined ? clock() : nil)
    }

    func openSession(activityID: ID) async throws -> WalkSession {
        let (host, guest) = try parties(of: activityID)
        if let i = walkSessions.lastIndex(where: { $0.activityId == activityID }) {
            if walkSessions[i].status.isOpen || walkSessions[i].status == .completed {
                let myID = db.meID
                if let p = walkSessions[i].participants.firstIndex(where: { $0.userId == myID }), walkSessions[i].participants[p].joinedAt == nil {
                    walkSessions[i].participants[p].joinedAt = clock()
                }
                return walkSessions[i]
            }
        }
        // The other person is "there" in the demo, so the session is ready as soon as you open it.
        let session = WalkSession(id: UUID().uuidString, activityId: activityID, status: .readyToStart,
                                  participants: [participant(host, role: "host", joined: true), participant(guest, role: "guest", joined: true)])
        walkSessions.append(session)
        return session
    }

    func session(activityID: ID) async throws -> WalkSession? { walkSessions.last { $0.activityId == activityID } }

    private func index(_ sessionID: ID) throws -> Int {
        guard let i = walkSessions.firstIndex(where: { $0.id == sessionID }) else { throw AlongError.notFound }
        return i
    }

    func setReady(sessionID: ID) async throws -> WalkSession {
        let i = try index(sessionID)
        if walkSessions[i].status == .active { return walkSessions[i] }
        guard walkSessions[i].status == .readyToStart || walkSessions[i].status == .awaitingParticipants else { throw AlongError.sessionClosed }
        let now = clock()
        for p in walkSessions[i].participants.indices { walkSessions[i].participants[p].readyAt = walkSessions[i].participants[p].readyAt ?? now }
        walkSessions[i].status = .active
        walkSessions[i].startedAt = now
        return walkSessions[i]
    }

    func setSharing(sessionID: ID, enabled: Bool) async throws -> WalkSession {
        let i = try index(sessionID)
        if enabled && walkSessions[i].status != .active { throw AlongError.sessionClosed }
        if let p = walkSessions[i].participants.firstIndex(where: { $0.userId == db.meID }) {
            walkSessions[i].participants[p].sharingStoppedAt = enabled ? nil : (walkSessions[i].participants[p].sharingStoppedAt ?? clock())
        }
        return walkSessions[i]
    }

    func finish(sessionID: ID, distanceMeters: Int?) async throws -> WalkSession {
        let i = try index(sessionID)
        guard walkSessions[i].status.isLive || walkSessions[i].status == .completed else { throw AlongError.sessionClosed }
        if walkSessions[i].status == .completed { return walkSessions[i] }
        let now = clock()
        let secs = max(Int(now.timeIntervalSince(walkSessions[i].startedAt ?? now)), 0)
        for p in walkSessions[i].participants.indices {
            walkSessions[i].participants[p].completionConfirmedAt = walkSessions[i].participants[p].completionConfirmedAt ?? now
            walkSessions[i].participants[p].sharingStoppedAt = walkSessions[i].participants[p].sharingStoppedAt ?? now
        }
        let planned = Int((db.activities.first { $0.id == walkSessions[i].activityId }.map {
            $0.walk.from.coordinate.distance(to: $0.walk.to.coordinate) } ?? 0).rounded())
        // Same clamp as the server: at most twice the planned route and 3 m/s.
        walkSessions[i].distanceMeters = max(min(distanceMeters ?? planned, max(planned * 2, 300), secs * 3), 0)
        walkSessions[i].durationSeconds = secs
        walkSessions[i].endedAt = now
        walkSessions[i].status = .completed
        return walkSessions[i]
    }

    func endEarly(sessionID: ID) async throws -> WalkSession {
        let i = try index(sessionID)
        guard walkSessions[i].status.isOpen else { return walkSessions[i] }
        walkSessions[i].status = walkSessions[i].status.isLive ? .endedEarly : .cancelled
        walkSessions[i].endedAt = clock()
        return walkSessions[i]
    }

    // MARK: History

    func history() async throws -> [CompletedWalk] {
        walkSessions.filter { $0.status == .completed }.compactMap { s -> CompletedWalk? in
            guard let a = db.activities.first(where: { $0.id == s.activityId }) else { return nil }
            let prefs = memoryPrefs[s.id] ?? (false, false)
            return CompletedWalk(id: s.id, title: a.title, startedAt: s.startedAt ?? s.endedAt ?? clock(),
                                 durationSeconds: s.durationSeconds ?? 0, distanceMeters: s.distanceMeters ?? 0,
                                 fromLabel: a.walk.from.publicLabel, toLabel: a.walk.to.publicLabel, area: a.walk.from.area,
                                 partnerName: nil, showOnProfile: prefs.show, revealPartner: prefs.reveal)
        }.sorted { $0.startedAt > $1.startedAt }
    }

    func stats() async throws -> WalkStats {
        let done = walkSessions.filter { $0.status == .completed }
        return WalkStats(walks: done.count, distanceMeters: done.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
                         durationSeconds: done.reduce(0) { $0 + ($1.durationSeconds ?? 0) })
    }

    func publicStats(userID: ID) async throws -> WalkStats? { userID == db.meID ? try await stats() : nil }

    func setMemoryPrefs(sessionID: ID, showOnProfile: Bool?, revealPartner: Bool?) async throws {
        var p = memoryPrefs[sessionID] ?? (false, false)
        if let showOnProfile { p.show = showOnProfile }
        if let revealPartner { p.reveal = revealPartner }
        memoryPrefs[sessionID] = p
    }
}

/// Demo-mode live channel: connects to nothing and receives nothing. (Never fabricates positions.)
actor MockLiveWalkService: LiveWalkService {
    func connect(sessionID: ID, myID: ID) async throws -> LiveWalkStreams {
        LiveWalkStreams(positions: AsyncStream { $0.finish() }, sessionChanged: AsyncStream { _ in }, connectionLost: AsyncStream { _ in })
    }
    func publish(_ position: LivePosition) async {}
    func disconnect() async {}
}
