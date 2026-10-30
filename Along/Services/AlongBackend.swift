import Foundation

// The service seams of the app. `Supabase*` types implement them against a real project; `MockAlongBackend`
// implements the data services in memory for demo mode, previews and tests.
// Mutations that change "my world" return a fresh `AlongSnapshot`; discovery is queried separately.

protocol AuthService: Sendable {
    /// Restores a persisted session (Keychain). `nil` when signed out.
    func restoreSession() async throws -> AuthSession?
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession
    /// Demo mode only. Real backends throw `AlongError.notAllowed`.
    func signInDemo() async throws -> AuthSession
    func signOut() async throws
    /// Deletes the account and everything it owns.
    func deleteAccount() async throws
    /// Emits whenever the session changes (sign-in, sign-out, expiry, refresh failure). `nil` = signed out.
    func sessionChanges() -> AsyncStream<AuthSession?>
}

protocol ProfileService: Sendable {
    func loadMyProfile() async throws -> MyProfile
    func completeProfile(_ draft: ProfileDraft, fullName: String?) async throws
    func updateProfile(_ user: User) async throws -> User
    func updateSettings(_ settings: UserSettings) async throws
}

protocol ActivityService: Sendable {
    /// The user's own world: hosted + requested plans, requests, chats, blocks.
    func loadSnapshot() async throws -> AlongSnapshot
    func discover(_ query: DiscoveryQuery) async throws -> DiscoveryPage
    func nearby(to center: Coordinate, radiusMeters: Double, kind: ActivityKind?, limit: Int) async throws -> DiscoveryPage
    func createActivity(_ draft: ActivityDraft) async throws -> AlongSnapshot
    func updateActivity(_ edit: ActivityEdit) async throws -> AlongSnapshot
    func cancelActivity(id: ID) async throws -> AlongSnapshot
}

protocol JoinRequestService: Sendable {
    func requestToJoin(activityID: ID) async throws -> AlongSnapshot
    func withdrawRequest(activityID: ID) async throws -> AlongSnapshot
    func respond(requestID: ID, accept: Bool) async throws -> AlongSnapshot
    func leave(activityID: ID) async throws -> AlongSnapshot
}

protocol MessagingService: Sendable {
    /// Returns the stored message (server id + timestamp).
    func sendMessage(conversationID: ID, text: String) async throws -> Message
    /// Newest-first page strictly older than `before` (or the latest page when nil), returned oldest-first.
    func loadMessages(conversationID: ID, before: Date?, limit: Int) async throws -> [Message]
}

protocol StorageService: Sendable {
    var supportsAvatars: Bool { get }
    /// Uploads JPEG data for the signed-in user and returns the stored object path.
    func uploadAvatar(_ jpeg: Data) async throws -> String
    func deleteAvatar(path: String) async throws
    /// Short-lived signed URL for an avatar path.
    func avatarURL(path: String) async throws -> URL
}

protocol SafetyService: Sendable {
    func block(userID: ID) async throws -> AlongSnapshot
    func unblock(userID: ID) async throws -> AlongSnapshot
    func report(_ target: ReportTarget, reason: ReportReason) async throws
}

/// Prototype-only helpers so one person can explore both sides of every flow (mock backend only).
protocol DemoService: Sendable {
    func simulateHostResponse(activityID: ID) async -> AlongSnapshot
    func simulateReply(conversationID: ID) async -> AlongSnapshot
    func resetDemo() async -> AlongSnapshot
}

/// Everything the UI's data layer needs once a user is signed in.
typealias AlongBackend = ProfileService & ActivityService & JoinRequestService & MessagingService & StorageService & SafetyService

/// Live updates pushed from the server. Nothing here exists in demo mode.
protocol RealtimeService: Sendable {
    /// Starts (or restarts — never duplicates) the subscriptions for this user.
    func start(userID: ID) async -> AsyncStream<RealtimeEvent>
    func stop() async
}
