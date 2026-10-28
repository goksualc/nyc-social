import Foundation

// The seams where Supabase (or any backend) plugs in. Every mutation returns the new `AlongSnapshot`
// the signed-in user is allowed to see. Swap `MockAlongBackend` for a network-backed type that
// conforms to `AlongBackend` and no view or view model needs to change.

protocol AuthService: Sendable {
    /// Phase 1: signs in as the local demo profile. Later: Sign in with Apple / email OTP, plus server-side age check.
    func signInDemo() async -> AlongSnapshot
}

protocol ActivityService: Sendable {
    func loadSnapshot() async -> AlongSnapshot
    func createActivity(_ draft: ActivityDraft) async throws -> AlongSnapshot
    func cancelActivity(id: ID) async throws -> AlongSnapshot
}

protocol RequestService: Sendable {
    func requestToJoin(activityID: ID) async throws -> AlongSnapshot
    func withdrawRequest(activityID: ID) async throws -> AlongSnapshot
    func respond(requestID: ID, accept: Bool) async throws -> AlongSnapshot
    func leave(activityID: ID) async throws -> AlongSnapshot
}

protocol MessagingService: Sendable {
    func sendMessage(conversationID: ID, text: String) async throws -> AlongSnapshot
}

protocol ProfileService: Sendable {
    func updateProfile(_ user: User) async -> AlongSnapshot
    func updateSettings(_ settings: UserSettings) async -> AlongSnapshot
}

protocol SafetyService: Sendable {
    func block(userID: ID) async -> AlongSnapshot
    func unblock(userID: ID) async -> AlongSnapshot
    func report(_ target: ReportTarget, reason: ReportReason) async
}

/// Prototype-only helpers so one person can explore both sides of every flow.
protocol DemoService: Sendable {
    func simulateHostResponse(activityID: ID) async -> AlongSnapshot
    func simulateReply(conversationID: ID) async -> AlongSnapshot
    func resetDemo() async -> AlongSnapshot
}

typealias AlongBackend = AuthService & ActivityService & RequestService & MessagingService
    & ProfileService & SafetyService & DemoService
