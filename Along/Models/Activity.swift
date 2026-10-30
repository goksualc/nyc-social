import Foundation
import CoreLocation

enum ActivityKind: String, Codable, Sendable, CaseIterable {
    case walk, cowork

    var label: String { self == .walk ? "Walk" : "Cowork" }
    var symbol: String { self == .walk ? "figure.walk" : "laptopcomputer" }
}

enum Pace: String, CaseIterable, Codable, Sendable, Identifiable {
    case casual = "Casual", moderate = "Moderate", fast = "Fast"
    var id: String { rawValue }
    var dbValue: String { rawValue.lowercased() }
}

enum WorkStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case deepWork = "Deep Work", social = "Social", buildTogether = "Build Together"
    var id: String { rawValue }
    var dbValue: String {
        switch self { case .deepWork: "deep_work"; case .social: "social"; case .buildTogether: "build_together" }
    }
    init?(dbValue: String) {
        switch dbValue {
        case "deep_work": self = .deepWork
        case "social": self = .social
        case "build_together": self = .buildTogether
        default: return nil
        }
    }
    /// Wording used on cards, e.g. "Focused work".
    var cardLabel: String {
        switch self {
        case .deepWork: "Focused work"
        case .social: "Social coworking"
        case .buildTogether: "Build together"
        }
    }
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

struct CoworkInfo: Hashable, Codable, Sendable {
    var venue: Place
    var style: WorkStyle
}

enum ActivityDetails: Hashable, Codable, Sendable {
    case walk(WalkInfo)
    case cowork(CoworkInfo)
}

struct Activity: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var title: String
    var hostID: ID
    var details: ActivityDetails
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

    var kind: ActivityKind {
        if case .walk = details { .walk } else { .cowork }
    }
    var walk: WalkInfo? { if case .walk(let w) = details { w } else { nil } }
    var cowork: CoworkInfo? { if case .cowork(let c) = details { c } else { nil } }

    var spotsLeft: Int { max(capacity - (participantCount ?? participantIDs.count), 0) }
    var isFull: Bool { spotsLeft == 0 }

    func isExpired(at now: Date) -> Bool { endDate <= now }
    func isActive(at now: Date) -> Bool { !isCancelled && !isExpired(at: now) }

    /// Public, general location text: "72nd St → 55th St" or "SoHo · Coffee shop".
    var publicLocationLabel: String {
        switch details {
        case .walk(let w): "\(w.from.publicLabel) → \(w.to.publicLabel)"
        case .cowork(let c): "\(c.venue.area) · Coffee shop"
        }
    }

    var detailLabel: String {
        switch details {
        case .walk(let w): "\(w.pace.rawValue) walk"
        case .cowork(let c): c.style.cardLabel
        }
    }

    var spotsLabel: String {
        switch spotsLeft {
        case 0: "Full"
        case 1: "1 spot open"
        default: "\(spotsLeft) spots open"
        }
    }

    /// Where the marker sits on the map (already approximate for non-members).
    var mapCoordinate: CLLocationCoordinate2D {
        switch details {
        case .walk(let w): w.from.coordinate.cl
        case .cowork(let c): c.venue.coordinate.cl
        }
    }

    var routeEndpoints: (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        guard let w = walk else { return nil }
        return (w.from.coordinate.cl, w.to.coordinate.cl)
    }
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
