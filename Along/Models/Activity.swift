import Foundation
import CoreLocation

enum ConversationTopic: String, CaseIterable, Codable, Sendable, Identifiable {
    case lifeLately = "Life Lately", career = "Career", relationships = "Relationships"
    case existential = "Existential Thoughts", random = "Random Thoughts", anything = "Anything, Really"
    var id: String { rawValue }
    var dbValue: String {
        switch self {
        case .lifeLately: "life_lately"; case .career: "career"; case .relationships: "relationships"
        case .existential: "existential"; case .random: "random"; case .anything: "anything"
        }
    }
    init?(dbValue: String) { if let t = Self.allCases.first(where: { $0.dbValue == dbValue }) { self = t } else { return nil } }
}

enum Pace: String, CaseIterable, Codable, Sendable, Identifiable {
    case casual = "Casual", moderate = "Moderate", fast = "Fast"
    var id: String { rawValue }
    var dbValue: String { rawValue.lowercased() }
}

enum Visibility: String, CaseIterable, Codable, Sendable, Identifiable {
    case `public` = "Public", `private` = "Private"
    var id: String { rawValue }
    var dbValue: String { rawValue.lowercased() }
}

struct WalkInfo: Hashable, Codable, Sendable {
    var from: Place
    var to: Place
    var pace: Pace
}

struct Activity: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var title: String
    var hostID: ID
    var walk: WalkInfo
    var startDate: Date
    var endDate: Date
    var visibility: Visibility
    var capacity: Int
    var participantIDs: [ID] = []
    /// Authoritative accepted-guest count when the server only sends a number (non-hosts never see guest IDs).
    var participantCount: Int?
    var note: String = ""
    /// Exact meeting instructions. The server only returns this to the host and accepted guests.
    var meetingDetails: String = ""
    /// The host's saved walking route (only sent to the host and accepted guests).
    var routeCoordinates: [Coordinate] = []
    /// True when the viewer is allowed to see exact places and `meetingDetails`.
    var hasPreciseAccess: Bool = false
    var isCancelled = false
    var createdAt: Date = .now
    /// The organizer chose to stay anonymous: the walk is public, their identity is not. `hostID` is then an opaque
    /// `anon:` alias for everyone except the organizer, and no profile can be looked up from it.
    var hostAnonymous = false
    /// The few interests an anonymous organizer chose to show (shown instead of a profile).
    /// Optional topic tags ("Tech", "Career"…). Stored under the host-interests column; empty for "Anonymous Host" walks.
    var hostInterests: [String] = []
    /// The optional "What's on your mind?" the host wrote. Shown naturally on the walk; never a category.
    var mindPrompt: String?

    var spotsLeft: Int { max(capacity - (participantCount ?? participantIDs.count), 0) }
    var isFull: Bool { spotsLeft == 0 }

    func isExpired(at now: Date) -> Bool { endDate <= now }
    func isActive(at now: Date) -> Bool { !isCancelled && !isExpired(at: now) }

    /// Public, general location text: "72nd St → 55th St".
    var publicLocationLabel: String { "\(walk.from.publicLabel) → \(walk.to.publicLabel)" }

    var detailLabel: String { "\(walk.pace.rawValue) walk" }

    var spotsLabel: String {
        switch spotsLeft {
        case 0: "Full"
        case 1: "1 spot open"
        default: "\(spotsLeft) spots open"
        }
    }

    /// Where the marker sits on the map (already approximate for non-members).
    var mapCoordinate: CLLocationCoordinate2D { walk.from.coordinate.cl }

    var routeEndpoints: (CLLocationCoordinate2D, CLLocationCoordinate2D) { (walk.from.coordinate.cl, walk.to.coordinate.cl) }
}

// MARK: - Requests & messaging

enum RequestStatus: String, Codable, Sendable {
    case pending, accepted, declined, withdrawn
}

struct JoinRequest: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var activityID: ID
    var requesterID: ID
    var status: RequestStatus = .pending
    var createdAt: Date = .now
}

struct Conversation: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var activityID: ID
    /// Set when the organizer opened the chat while the request was still pending.
    var requestID: ID?
    /// Always exactly two people: the host and one accepted guest.
    var participantIDs: [ID]
    var createdAt: Date = .now
}

struct Message: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var conversationID: ID
    var senderID: ID
    var text: String
    var sentAt: Date = .now
}
