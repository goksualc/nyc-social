import Foundation

/// Everything the signed-in user is allowed to see *about their own world*: their plans, requests, chats and
/// blocks. Public discovery results are loaded separately (see `DiscoveryQuery`) so the app never downloads
/// every activity. A real backend returns this already filtered by Row Level Security.
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
    /// Walking route vertices (optional) so the server stores the real route, not a straight line.
    var routeCoordinates: [Coordinate] = []
}

/// Fields a host may change after publishing. `nil` = unchanged. Locations can't be edited.
struct ActivityEdit: Sendable {
    var activityID: ID
    var startDate: Date?
    var endDate: Date?
    var capacity: Int?
    var note: String?
    var meetingDetails: String?
}

/// A map-bounded, filtered, paginated discovery request.
struct DiscoveryQuery: Sendable, Equatable {
    var minLat: Double, minLng: Double, maxLat: Double, maxLng: Double
    var kind: ActivityKind?
    /// Plans overlapping [from, to]; `nil` = from now / open-ended.
    var from: Date?
    var to: Date?
    var limit = 50
    var offset = 0
}

struct DiscoveryPage: Sendable {
    var activities: [Activity]
    /// Minimal host identities from the cards, for hosts whose full profile isn't readable.
    var hosts: [User]
    var hasMore: Bool
}

/// The signed-in identity, independent of the backend that produced it.
struct AuthSession: Equatable, Sendable {
    var userID: ID
}

/// Lets the app decide whether first-run profile completion is needed.
struct MyProfile: Sendable {
    var user: User
    var fullName: String?
    var hasDisplayName: Bool
    var ageConfirmed: Bool
    var visibility: ProfileVisibility = .everyone
    var isComplete: Bool { hasDisplayName && ageConfirmed }
}

struct ProfileDraft: Sendable {
    var displayName: String
    var bio: String
    var interests: [Interest]
    var alongFor: Set<AlongPurpose>
    var confirmAge: Bool
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

/// Realtime events the store reacts to. They carry only what the server already authorised for this user.
enum RealtimeEvent: Sendable {
    case requestsChanged
    case activityChanged
    case conversationsChanged
    case message(Message)
    /// The socket (re)connected; anything may have changed while we were away.
    case reconnected
}
