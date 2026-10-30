import Foundation
import Supabase

// MARK: - Auth

final class SupabaseAuthService: AuthService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    private func map(_ s: Session) -> AuthSession { AuthSession(userID: s.user.id.uuidString.lowercased()) }

    /// Reads the Keychain-persisted session without a network round trip, so the app opens offline too.
    /// The SDK refreshes an expired access token transparently on the next request.
    func restoreSession() async throws -> AuthSession? {
        client.auth.currentSession.map(map)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        return map(session)
    }

    func signInDemo() async throws -> AuthSession { throw AlongError.notAllowed }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut(scope: .local)
    }

    func sessionChanges() -> AsyncStream<AuthSession?> {
        let stream = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in stream {
                    switch change.event {
                    case .signedOut, .userDeleted: continuation.yield(nil)
                    default: continuation.yield(change.session.map(self.map))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Profile

struct MyProfileRow: Decodable {
    var id: String
    var username: String?
    var fullName: String?
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var interests: [String]?
    var lookingFor: [String]?
    var visibility: String?
    var ageConfirmedAt: Date?
}

final class SupabaseProfileService: ProfileService, @unchecked Sendable {
    private let manager: SupabaseManager
    private let local = LocalSettingsStore()
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    func loadMyProfile() async throws -> MyProfile {
        var rows: [MyProfileRow] = try await client.rpc("get_my_profile").execute().value
        if rows.isEmpty {                                   // trigger missed (e.g. account predates migrations)
            try await client.rpc("ensure_profile").execute()
            rows = try await client.rpc("get_my_profile").execute().value
        }
        guard let r = rows.first else { throw AlongError.notFound }
        let base = ProfileRow(id: r.id, username: r.username, fullName: r.fullName, displayName: r.displayName, bio: r.bio,
                              avatarUrl: r.avatarUrl, interests: r.interests, lookingFor: r.lookingFor,
                              visibility: r.visibility, ageConfirmedAt: r.ageConfirmedAt)
        return MyProfile(user: base.user, fullName: r.fullName,
                         hasDisplayName: !(r.displayName ?? "").isEmpty, ageConfirmed: r.ageConfirmedAt != nil,
                         visibility: ProfileVisibility(dbValue: r.visibility ?? "everyone"))
    }

    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws {
        try await client.rpc("complete_profile", params: CompleteProfileParams(
            pDisplayName: draft.displayName, pBio: draft.bio, pInterests: draft.interests.map(\.dbValue),
            pLookingFor: draft.alongFor.map(\.dbValue), pConfirmAge: draft.confirmAge)).execute()
        if let fullName, !fullName.isEmpty, let uid = manager.currentUserID {
            // Best effort: keep Apple's one-time name server-side (private column, never shown to others).
            _ = try? await client.from("profiles").update(["full_name": fullName], returning: .minimal).eq("id", value: uid).execute()
        }
    }

    func updateProfile(_ user: User) async throws -> User {
        let uid = try manager.requireUserID()
        let name = String(user.firstName.trimmingCharacters(in: .whitespaces).prefix(24))
        guard !name.isEmpty else { throw AlongError.profileIncomplete }
        let update = ProfileUpdate(displayName: name, bio: String(user.bio.prefix(160)),
                                   interests: user.interests.map(\.dbValue),
                                   lookingFor: user.alongFor.map(\.dbValue), avatarUrl: user.avatarPath,
                                   visibility: nil)
        // `.minimal`: the default asks for the full row back, which would hit the column grants that hide private columns.
        try await client.from("profiles").update(update, returning: .minimal).eq("id", value: uid).execute()
        var saved = user
        saved.firstName = name
        return saved
    }

    func updateSettings(_ settings: UserSettings) async throws {
        let uid = try manager.requireUserID()
        local.save(settings, for: uid)
        struct Vis: Encodable { var visibility: String }
        try await client.from("profiles").update(Vis(visibility: settings.profileVisibility.dbValue), returning: .minimal).eq("id", value: uid).execute()
    }
}

// MARK: - Activities

final class SupabaseActivityService: ActivityService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    private var loader: SupabaseSnapshotLoader { SupabaseSnapshotLoader(manager: manager) }
    init(manager: SupabaseManager) { self.manager = manager }

    func loadSnapshot() async throws -> AlongSnapshot { try await loader.load() }

    func discover(_ q: DiscoveryQuery) async throws -> DiscoveryPage {
        let rows: [ActivityCardRow] = try await client.rpc("discover_activities", params: DiscoverParams(
            pMinLng: q.minLng, pMinLat: q.minLat, pMaxLng: q.maxLng, pMaxLat: q.maxLat,
            pType: q.kind?.rawValue, pFrom: q.from, pTo: q.to, pLimit: q.limit + 1, pOffset: q.offset)).execute().value
        return page(from: rows, limit: q.limit)
    }

    func nearby(to center: Coordinate, radiusMeters: Double, kind: ActivityKind?, limit: Int) async throws -> DiscoveryPage {
        let rows: [ActivityCardRow] = try await client.rpc("nearby_activities", params: NearbyParams(
            pLng: center.longitude, pLat: center.latitude, pRadiusM: radiusMeters,
            pType: kind?.rawValue, pLimit: limit + 1)).execute().value
        return page(from: rows, limit: limit)
    }

    /// Asks for one extra row so `hasMore` is exact without a count query.
    private func page(from rows: [ActivityCardRow], limit: Int) -> DiscoveryPage {
        let shown = Array(rows.prefix(limit))
        return DiscoveryPage(activities: shown.map { $0.activity() }, hosts: shown.map(\.host), hasMore: rows.count > limit)
    }

    func createActivity(_ d: ActivityDraft) async throws -> AlongSnapshot {
        switch d.details {
        case .walk(let w):
            let route = d.routeCoordinates.count >= 2 ? d.routeCoordinates.map { [$0.longitude, $0.latitude] } : nil
            let _: String = try await client.rpc("create_walk", params: CreateWalkParams(
                pTitle: d.title, pDescription: d.note, pStartTime: d.startDate, pEndTime: d.endDate,
                pMaxParticipants: d.capacity, pVisibility: d.visibility.rawValue.lowercased(), pPace: w.pace.dbValue,
                pStartLabel: w.from.publicLabel, pEndLabel: w.to.publicLabel,
                pStartLng: w.from.coordinate.longitude, pStartLat: w.from.coordinate.latitude,
                pEndLng: w.to.coordinate.longitude, pEndLat: w.to.coordinate.latitude,
                pRoute: route, pMeetingDetails: d.meetingDetails)).execute().value
        case .cowork(let c):
            let _: String = try await client.rpc("create_cowork", params: CreateCoworkParams(
                pTitle: d.title, pDescription: d.note, pStartTime: d.startDate, pEndTime: d.endDate,
                pMaxParticipants: d.capacity, pVisibility: d.visibility.rawValue.lowercased(), pWorkStyle: c.style.dbValue,
                pCafeName: c.venue.name, pAddress: c.venue.address ?? "",
                pLng: c.venue.coordinate.longitude, pLat: c.venue.coordinate.latitude,
                pPlaceIdentifier: "", pMeetingDetails: d.meetingDetails)).execute().value
        }
        return try await loader.load()
    }

    func updateActivity(_ e: ActivityEdit) async throws -> AlongSnapshot {
        try await client.rpc("update_activity", params: UpdateActivityParams(
            pActivityId: e.activityID, pStartTime: e.startDate, pEndTime: e.endDate,
            pMaxParticipants: e.capacity, pDescription: e.note, pMeetingDetails: e.meetingDetails)).execute()
        return try await loader.load()
    }

    func cancelActivity(id: ID) async throws -> AlongSnapshot {
        try await client.rpc("cancel_activity", params: ["p_activity_id": id]).execute()
        return try await loader.load()
    }
}

// MARK: - Join requests

final class SupabaseJoinRequestService: JoinRequestService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    private var loader: SupabaseSnapshotLoader { SupabaseSnapshotLoader(manager: manager) }
    init(manager: SupabaseManager) { self.manager = manager }

    func requestToJoin(activityID: ID) async throws -> AlongSnapshot {
        let _: String = try await client.rpc("request_to_join", params: ["p_activity_id": activityID]).execute().value
        return try await loader.load()
    }

    func withdrawRequest(activityID: ID) async throws -> AlongSnapshot {
        let uid = try manager.requireUserID()
        let rows: [JoinRequestRow] = try await client.from("join_requests")
            .select("id, activity_id, requester_id, status, created_at")
            .eq("activity_id", value: activityID).eq("requester_id", value: uid).eq("status", value: "pending")
            .limit(1).execute().value
        guard let request = rows.first else { throw AlongError.notFound }
        try await client.rpc("cancel_join_request", params: ["p_request_id": request.id]).execute()
        return try await loader.load()
    }

    func respond(requestID: ID, accept: Bool) async throws -> AlongSnapshot {
        struct P: Encodable { var pRequestId: String; var pAccept: Bool }
        let _: String = try await client.rpc("respond_to_join_request", params: P(pRequestId: requestID, pAccept: accept))
            .execute().value
        return try await loader.load()
    }

    func leave(activityID: ID) async throws -> AlongSnapshot {
        try await client.rpc("leave_activity", params: ["p_activity_id": activityID]).execute()
        return try await loader.load()
    }
}

// MARK: - Messaging

final class SupabaseMessagingService: MessagingService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    func sendMessage(conversationID: ID, text: String) async throws -> Message {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AlongError.notAllowed }
        do {
            let row: MessageRow = try await client.from("messages")
                .insert(MessageInsert(conversationId: conversationID, content: String(trimmed.prefix(2000))))
                .select(SupabaseSnapshotLoader.messageColumns).single().execute().value
            return row.message
        } catch let error as PostgrestError where error.code == "42501" {
            throw AlongError.chatClosed               // RLS: conversation closed, blocked, or not a participant
        }
    }

    func loadMessages(conversationID: ID, before: Date?, limit: Int) async throws -> [Message] {
        var query = client.from("messages").select(SupabaseSnapshotLoader.messageColumns)
            .eq("conversation_id", value: conversationID)
        if let before { query = query.lt("created_at", value: SupabaseCoding.format(before)) }
        let rows: [MessageRow] = try await query
            .order("created_at", ascending: false).order("id", ascending: false)
            .limit(limit).execute().value
        return rows.reversed().map(\.message)
    }
}

// MARK: - Storage (avatars)

final class SupabaseStorageService: StorageService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var bucket: StorageFileApi { manager.client.storage.from("avatars") }
    init(manager: SupabaseManager) { self.manager = manager }

    var supportsAvatars: Bool { true }

    func uploadAvatar(_ jpeg: Data) async throws -> String {
        guard jpeg.count <= 2_000_000 else { throw AlongError.imageTooLarge }
        let uid = try manager.requireUserID()
        let path = "\(uid)/avatar-\(Int(Date().timeIntervalSince1970)).jpg"
        _ = try await bucket.upload(path, data: jpeg, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false))
        return path
    }

    func deleteAvatar(path: String) async throws {
        _ = try await bucket.remove(paths: [path])
    }

    func avatarURL(path: String) async throws -> URL {
        try await bucket.createSignedURL(path: path, expiresIn: 3600)
    }
}

// MARK: - Safety

final class SupabaseSafetyService: SafetyService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    private var loader: SupabaseSnapshotLoader { SupabaseSnapshotLoader(manager: manager) }
    init(manager: SupabaseManager) { self.manager = manager }

    func block(userID: ID) async throws -> AlongSnapshot {
        try await client.rpc("block_user", params: ["p_user_id": userID]).execute()
        return try await loader.load()
    }

    func unblock(userID: ID) async throws -> AlongSnapshot {
        try await client.rpc("unblock_user", params: ["p_user_id": userID]).execute()
        return try await loader.load()
    }

    func report(_ target: ReportTarget, reason: ReportReason) async throws {
        struct P: Encodable { var pTargetType: String; var pTargetId: String; var pReason: String }
        let (type, id): (String, ID)
        switch target { case .user(let u): (type, id) = ("user", u); case .activity(let a): (type, id) = ("activity", a) }
        let code: String
        switch reason { case .inappropriate: code = "inappropriate"; case .unsafe: code = "unsafe"; case .spam: code = "spam"; case .other: code = "other" }
        try await client.rpc("report_content", params: P(pTargetType: type, pTargetId: id, pReason: code)).execute()
    }
}

// MARK: - Composition

/// The signed-in backend: one object conforming to every data service, forwarding to focused implementations.
final class SupabaseBackend: AlongBackend, @unchecked Sendable {
    let manager: SupabaseManager
    private let profiles: SupabaseProfileService
    private let activities: SupabaseActivityService
    private let requests: SupabaseJoinRequestService
    private let messaging: SupabaseMessagingService
    private let storage: SupabaseStorageService
    private let safety: SupabaseSafetyService

    init(manager: SupabaseManager) {
        self.manager = manager
        profiles = .init(manager: manager); activities = .init(manager: manager); requests = .init(manager: manager)
        messaging = .init(manager: manager); storage = .init(manager: manager); safety = .init(manager: manager)
    }

    // ProfileService
    func loadMyProfile() async throws -> MyProfile { try await profiles.loadMyProfile() }
    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws { try await profiles.completeProfile(draft, fullName: fullName) }
    func updateProfile(_ user: User) async throws -> User { try await profiles.updateProfile(user) }
    func updateSettings(_ settings: UserSettings) async throws { try await profiles.updateSettings(settings) }
    // ActivityService
    func loadSnapshot() async throws -> AlongSnapshot { try await activities.loadSnapshot() }
    func discover(_ query: DiscoveryQuery) async throws -> DiscoveryPage { try await activities.discover(query) }
    func nearby(to c: Coordinate, radiusMeters: Double, kind: ActivityKind?, limit: Int) async throws -> DiscoveryPage {
        try await activities.nearby(to: c, radiusMeters: radiusMeters, kind: kind, limit: limit)
    }
    func createActivity(_ draft: ActivityDraft) async throws -> AlongSnapshot { try await activities.createActivity(draft) }
    func updateActivity(_ edit: ActivityEdit) async throws -> AlongSnapshot { try await activities.updateActivity(edit) }
    func cancelActivity(id: ID) async throws -> AlongSnapshot { try await activities.cancelActivity(id: id) }
    // JoinRequestService
    func requestToJoin(activityID: ID) async throws -> AlongSnapshot { try await requests.requestToJoin(activityID: activityID) }
    func withdrawRequest(activityID: ID) async throws -> AlongSnapshot { try await requests.withdrawRequest(activityID: activityID) }
    func respond(requestID: ID, accept: Bool) async throws -> AlongSnapshot { try await requests.respond(requestID: requestID, accept: accept) }
    func leave(activityID: ID) async throws -> AlongSnapshot { try await requests.leave(activityID: activityID) }
    // MessagingService
    func sendMessage(conversationID: ID, text: String) async throws -> Message { try await messaging.sendMessage(conversationID: conversationID, text: text) }
    func loadMessages(conversationID: ID, before: Date?, limit: Int) async throws -> [Message] {
        try await messaging.loadMessages(conversationID: conversationID, before: before, limit: limit)
    }
    // StorageService
    var supportsAvatars: Bool { storage.supportsAvatars }
    func uploadAvatar(_ jpeg: Data) async throws -> String { try await storage.uploadAvatar(jpeg) }
    func deleteAvatar(path: String) async throws { try await storage.deleteAvatar(path: path) }
    func avatarURL(path: String) async throws -> URL { try await storage.avatarURL(path: path) }
    // SafetyService
    func block(userID: ID) async throws -> AlongSnapshot { try await safety.block(userID: userID) }
    func unblock(userID: ID) async throws -> AlongSnapshot { try await safety.unblock(userID: userID) }
    func report(_ target: ReportTarget, reason: ReportReason) async throws { try await safety.report(target, reason: reason) }
}
