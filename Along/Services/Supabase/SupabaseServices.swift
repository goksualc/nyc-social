import Foundation
import Supabase

// MARK: - Auth

final class SupabaseAuthService: AuthService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    private func map(_ s: Session) -> AuthSession { AuthSession(userID: s.user.id.uuidString.lowercased()) }

    /// Restores the Keychain session. An expired access token is refreshed; if the refresh is rejected the session is
    /// dropped. With no connection the stored session is used as-is so the app still opens.
    func restoreSession() async throws -> AuthSession? {
        guard let stored = client.auth.currentSession else { return nil }
        do {
            return map(try await client.auth.session)
        } catch {
            switch ErrorPresenter.map(error) {
            case .offline: return map(stored)
            case .sessionExpired:
                try? await client.auth.signOut(scope: .local)
                return nil
            default: return map(stored)
            }
        }
    }

    func signInWithGoogle() async throws -> AuthSession {
        let session = try await client.auth.signInWithOAuth(
            provider: .google, redirectTo: AuthRedirect.url(.oauth),
            queryParams: [(name: "prompt", value: "select_account")])
        return map(session)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        map(try await client.auth.signIn(email: email, password: password))
    }

    func signUp(email: String, password: String, fullName: String) async throws -> SignUpOutcome {
        do {
            let response = try await client.auth.signUp(
                email: email, password: password, data: ["full_name": .string(fullName)],
                redirectTo: AuthRedirect.url(.verify))
            switch response {
            case .session(let session): return .signedIn(map(session))
            case .user: return .verificationRequired(email: email)
            }
        } catch let error as AuthError {
            // Never reveal that an address is already registered: look identical to a fresh sign-up.
            if case .api(_, let code, _, _) = error, code == .userAlreadyExists || code == .emailExists {
                return .verificationRequired(email: email)
            }
            throw error
        }
    }

    func resendVerification(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup, emailRedirectTo: AuthRedirect.url(.verify))
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: AuthRedirect.url(.recovery))
    }

    func updatePassword(_ newPassword: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    func handleAuthLink(_ url: URL) async throws -> AuthLinkResult {
        guard let kind = AuthRedirect.kind(of: url) else { throw AlongError.invalidLink }
        // PKCE: the one-time code is only redeemable with the verifier stored on this device.
        let session = try await client.auth.session(from: url)
        return AuthLinkResult(kind: kind, session: map(session))
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
    var base: ProfileRow
    var birthday: String?
    var showAge: Bool?
    var showWalkStats: Bool?
    var onboardingCompleted: Bool?

    private enum Extra: String, CodingKey { case birthday, showAge, showWalkStats, onboardingCompleted }
    init(from decoder: Decoder) throws {
        base = try ProfileRow(from: decoder)
        let c = try decoder.container(keyedBy: Extra.self)
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday)
        showAge = try c.decodeIfPresent(Bool.self, forKey: .showAge)
        showWalkStats = try c.decodeIfPresent(Bool.self, forKey: .showWalkStats)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
    }
}

enum ProfileDates {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
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
        var user = r.base.user
        let birthday = r.birthday.flatMap { ProfileDates.formatter.date(from: $0) }
        if let birthday { user.age = Calendar.current.dateComponents([.year], from: birthday, to: .now).year }
        return MyProfile(user: user, fullName: r.base.fullName,
                         hasDisplayName: !(r.base.displayName ?? "").isEmpty, ageConfirmed: r.base.ageConfirmedAt != nil,
                         // Servers that predate migration 8 have no onboarding flag: don't send existing members back through it.
                         onboardingCompleted: r.onboardingCompleted ?? true, birthday: birthday,
                         visibility: ProfileVisibility(dbValue: r.base.visibility ?? "everyone"),
                         showAge: r.showAge ?? false, showWalkStats: r.showWalkStats ?? false)
    }

    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws {
        try await client.rpc("complete_profile", params: CompleteProfileParams(
            pDisplayName: draft.displayName, pBio: draft.bio, pInterests: [],
            pLookingFor: ["walking_buddies"], pConfirmAge: draft.confirmAge)).execute()
        let uid = try manager.requireUserID()
        let extras = OnboardingUpdate(
            instagramUsername: draft.instagram, xUsername: draft.xHandle, hobbies: draft.hobbies,
            preferredPace: draft.pacePreference?.dbValue, preferredDuration: draft.preferredDuration,
            favoriteNeighborhoods: draft.favoriteNeighborhoods,
            birthday: draft.birthday.map { ProfileDates.formatter.string(from: $0) })
        try await client.from("profiles").update(extras, returning: .minimal).eq("id", value: uid).execute()
        try await client.rpc("complete_onboarding").execute()
        if let fullName, !fullName.isEmpty {
            // Best effort: keep Apple's one-time name server-side (private column, never shown to others).
            _ = try? await client.from("profiles").update(["full_name": fullName], returning: .minimal).eq("id", value: uid).execute()
        }
    }

    func updateProfile(_ user: User) async throws -> User {
        let uid = try manager.requireUserID()
        let name = String(user.firstName.trimmingCharacters(in: .whitespaces).prefix(24))
        guard !name.isEmpty else { throw AlongError.profileIncomplete }
        func clean(_ s: String?, _ limit: Int) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : String(t.prefix(limit))
        }
        let update = ProfileUpdate(
            displayName: name, bio: String(user.bio.prefix(160)), hobbies: Array(user.hobbies.prefix(HobbyCatalog.maxSelected)),
            instagramUsername: user.instagram.flatMap { SocialNetwork.instagram.username(from: $0) },
            xUsername: user.xHandle.flatMap { SocialNetwork.x.username(from: $0) },
            occupation: clean(user.occupation, 60), university: clean(user.university, 80),
            languages: Array(user.languages.prefix(Languages.maxSelected)),
            favoriteNeighborhoods: Array(user.favoriteNeighborhoods.prefix(Neighborhoods.maxSelected)),
            preferredPace: user.pacePreference?.dbValue, preferredDuration: user.preferredDuration,
            discussionTopics: user.discussionTopics.map(\.dbValue),
            conversationCustom: Array(user.conversationCustom.prefix(3)), visibility: nil)
        // `.minimal`: the default asks for the full row back, which would hit the column grants that hide private columns.
        try await client.from("profiles").update(update, returning: .minimal).eq("id", value: uid).execute()
        var saved = user
        saved.firstName = name
        return saved
    }

    func updateAvatarPath(_ path: String?) async throws {
        let uid = try manager.requireUserID()
        // `.minimal`: the default asks for the full row back, which would hit the column grants that hide private columns.
        try await client.from("profiles").update(AvatarUpdate(avatarUrl: path), returning: .minimal).eq("id", value: uid).execute()
    }

    func updateSettings(_ settings: UserSettings) async throws {
        let uid = try manager.requireUserID()
        local.save(settings, for: uid)
        struct Prefs: Encodable { var visibility: String; var showAge: Bool; var showWalkStats: Bool }
        do {
            try await client.from("profiles").update(Prefs(visibility: settings.profileVisibility.dbValue, showAge: settings.showAge,
                                                           showWalkStats: settings.showWalkStats), returning: .minimal)
                .eq("id", value: uid).execute()
        } catch {
            // Servers that predate migration 8: keep the visibility change working.
            struct Vis: Encodable { var visibility: String }
            try await client.from("profiles").update(Vis(visibility: settings.profileVisibility.dbValue), returning: .minimal).eq("id", value: uid).execute()
        }
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
            pType: "walk", pFrom: q.from, pTo: q.to, pLimit: q.limit + 1, pOffset: q.offset)).execute().value
        return page(from: rows, limit: q.limit)
    }

    func nearby(to center: Coordinate, radiusMeters: Double, limit: Int) async throws -> DiscoveryPage {
        let rows: [ActivityCardRow] = try await client.rpc("nearby_activities", params: NearbyParams(
            pLng: center.longitude, pLat: center.latitude, pRadiusM: radiusMeters,
            pType: "walk", pLimit: limit + 1)).execute().value
        return page(from: rows, limit: limit)
    }

    func searchAlongRoute(_ q: RouteSearchQuery) async throws -> [RouteMatch] {
        // PostGIS does all the matching; the device only sends the route (thinned) and shows what comes back.
        let rows: [RouteMatchRow] = try await client.rpc("search_walks_along_route", params: RouteSearchParams(
            pRoute: Self.thin(q.route, to: 300).map { [$0.longitude, $0.latitude] }, pCorridorM: q.corridorMeters,
            pFrom: q.from, pTo: q.to, pWhen: nil, pLimit: q.limit)).execute().value
        return rows.map { $0.match() }
    }

    private static func thin(_ c: [Coordinate], to n: Int) -> [Coordinate] {
        guard c.count > n, n >= 2 else { return c }
        let step = Double(c.count - 1) / Double(n - 1)
        return (0..<n).map { c[min(c.count - 1, Int((Double($0) * step).rounded()))] }
    }

    /// Asks for one extra row so `hasMore` is exact without a count query.
    private func page(from rows: [ActivityCardRow], limit: Int) -> DiscoveryPage {
        let shown = Array(rows.prefix(limit))
        return DiscoveryPage(activities: shown.map { $0.activity() }, hosts: shown.map(\.host), hasMore: rows.count > limit)
    }

    func createActivity(_ d: ActivityDraft) async throws -> AlongSnapshot {
        let w = d.walk
        let route = d.routeCoordinates.count >= 2 ? d.routeCoordinates.map { [$0.longitude, $0.latitude] } : nil
        let _: String = try await client.rpc("create_walk", params: CreateWalkParams(
                pTitle: d.title, pDescription: d.note, pStartTime: d.startDate, pEndTime: d.endDate,
                pMaxParticipants: d.capacity, pVisibility: "public", pPace: w.pace.dbValue,   // a walk is always on the map; anonymity is its own flag
                pStartLabel: w.from.publicLabel, pEndLabel: w.to.publicLabel,
                pStartLng: w.from.coordinate.longitude, pStartLat: w.from.coordinate.latitude,
                pEndLng: w.to.coordinate.longitude, pEndLat: w.to.coordinate.latitude,
                pRoute: route, pMeetingDetails: d.meetingDetails,
                pAnonymousHost: d.anonymousHost, pHostInterests: d.anonymousHost ? Array(d.hostInterests.prefix(4)) : [],
                pMindPrompt: String(d.mindPrompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)))).execute().value
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
        // avatars/<user id>/avatar-<unix milliseconds>.jpg — unique per upload (two quick uploads can't collide) and matching the
        // storage policy's `avatar(-digits)?.jpg` pattern, which only allows writes inside the caller's own folder.
        let path = AvatarStoragePath.make(userID: uid)
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
    private let walks: SupabaseWalkSessionService
    private let walkHistory: SupabaseWalkHistoryService

    init(manager: SupabaseManager) {
        self.manager = manager
        profiles = .init(manager: manager); activities = .init(manager: manager); requests = .init(manager: manager)
        messaging = .init(manager: manager); storage = .init(manager: manager); safety = .init(manager: manager)
        walks = .init(manager: manager); walkHistory = .init(manager: manager)
    }

    // ProfileService
    func loadMyProfile() async throws -> MyProfile { try await profiles.loadMyProfile() }
    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws { try await profiles.completeProfile(draft, fullName: fullName) }
    func updateProfile(_ user: User) async throws -> User { try await profiles.updateProfile(user) }
    func updateAvatarPath(_ path: String?) async throws { try await profiles.updateAvatarPath(path) }
    func updateSettings(_ settings: UserSettings) async throws { try await profiles.updateSettings(settings) }
    // ActivityService
    func loadSnapshot() async throws -> AlongSnapshot { try await activities.loadSnapshot() }
    func discover(_ query: DiscoveryQuery) async throws -> DiscoveryPage { try await activities.discover(query) }
    func nearby(to c: Coordinate, radiusMeters: Double, limit: Int) async throws -> DiscoveryPage {
        try await activities.nearby(to: c, radiusMeters: radiusMeters, limit: limit)
    }
    func searchAlongRoute(_ query: RouteSearchQuery) async throws -> [RouteMatch] { try await activities.searchAlongRoute(query) }
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
    // WalkSessionService
    func openSession(activityID: ID) async throws -> WalkSession { try await walks.openSession(activityID: activityID) }
    func session(activityID: ID) async throws -> WalkSession? { try await walks.session(activityID: activityID) }
    func setReady(sessionID: ID) async throws -> WalkSession { try await walks.setReady(sessionID: sessionID) }
    func setSharing(sessionID: ID, enabled: Bool) async throws -> WalkSession { try await walks.setSharing(sessionID: sessionID, enabled: enabled) }
    func finish(sessionID: ID, distanceMeters: Int?) async throws -> WalkSession { try await walks.finish(sessionID: sessionID, distanceMeters: distanceMeters) }
    func endEarly(sessionID: ID) async throws -> WalkSession { try await walks.endEarly(sessionID: sessionID) }
    // WalkHistoryService
    func history() async throws -> [CompletedWalk] { try await walkHistory.history() }
    func stats() async throws -> WalkStats { try await walkHistory.stats() }
    func publicStats(userID: ID) async throws -> WalkStats? { try await walkHistory.publicStats(userID: userID) }
    func setMemoryPrefs(sessionID: ID, showOnProfile: Bool?, revealPartner: Bool?) async throws {
        try await walkHistory.setMemoryPrefs(sessionID: sessionID, showOnProfile: showOnProfile, revealPartner: revealPartner)
    }
}
