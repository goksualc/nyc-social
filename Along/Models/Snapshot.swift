import Foundation

/// Everything the signed-in user is allowed to see. A real backend would return this (or deltas of it)
/// already filtered by Row Level Security; the mock backend does the same filtering in-process.
struct AlongSnapshot: Sendable {
    var me: User
    var settings: UserSettings
    var users: [User]
    var activities: [Activity]
    var requests: [JoinRequest]
    var conversations: [Conversation]
    var messages: [Message]
    var blockedUserIDs: Set<ID>
}

/// What the create flow hands to the backend.
struct ActivityDraft: Sendable {
    var title: String
    var details: ActivityDetails
    var startDate: Date
    var endDate: Date
    var visibility: Visibility
    var capacity: Int
    var note: String
    var meetingDetails: String
}

enum ReportReason: String, CaseIterable, Sendable, Identifiable {
    case inappropriate = "Inappropriate behaviour"
    case unsafe = "Made me feel unsafe"
    case spam = "Spam or fake profile"
    case other = "Something else"
    var id: String { rawValue }
}

enum ReportTarget: Sendable {
    case user(ID)
    case activity(ID)
}

enum AlongError: LocalizedError, Sendable {
    case outsideManhattan
    case startInPast
    case invalidTimes
    case sameLocation
    case notFound
    case notAllowed
    case activityFull
    case alreadyRequested
    case blocked
    case chatClosed

    var errorDescription: String? {
        switch self {
        case .outsideManhattan: "Along is only in Manhattan for now."
        case .startInPast: "Pick a time in the future."
        case .invalidTimes: "The end time needs to be after the start."
        case .sameLocation: "Start and destination can't be the same."
        case .notFound: "That plan is no longer available."
        case .notAllowed: "You can't do that."
        case .activityFull: "This plan is full."
        case .alreadyRequested: "You've already asked to join."
        case .blocked: "That's not available."
        case .chatClosed: "This conversation is closed."
        }
    }
}
