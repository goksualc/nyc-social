import Foundation
import CoreLocation

/// The server-authoritative lifecycle of a shared walk. The app only ever *displays* this; transitions happen in Postgres.
enum WalkSessionStatus: String, Codable, Sendable {
    case awaitingParticipants = "awaiting_participants"
    case readyToStart = "ready_to_start"
    case active
    case awaitingCompletion = "awaiting_completion"
    case completed, cancelled
    case endedEarly = "ended_early"
    case expired

    var isLive: Bool { self == .active || self == .awaitingCompletion }
    var isOpen: Bool { self == .awaitingParticipants || self == .readyToStart || isLive }
    var title: String {
        switch self {
        case .awaitingParticipants: "Awaiting participants"
        case .readyToStart: "Ready to start"
        case .active: "Walk in progress"
        case .awaitingCompletion: "Awaiting completion"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .endedEarly: "Ended early"
        case .expired: "Expired"
        }
    }
}

struct WalkSessionParticipant: Codable, Hashable, Sendable, Identifiable {
    var userId: ID
    var role: String
    var displayName: String
    var avatarPath: String?
    var joinedAt: Date?
    var readyAt: Date?
    var completionConfirmedAt: Date?
    var sharingStoppedAt: Date?
    var id: ID { userId }
    var isReady: Bool { readyAt != nil }
    var isSharing: Bool { sharingStoppedAt == nil }
    var hasConfirmedFinish: Bool { completionConfirmedAt != nil }
}

struct WalkSession: Codable, Hashable, Sendable, Identifiable {
    var id: ID
    var activityId: ID
    var status: WalkSessionStatus
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?
    var distanceMeters: Int?
    var completionDeadline: Date?
    var participants: [WalkSessionParticipant]

    func participant(_ userID: ID) -> WalkSessionParticipant? { participants.first { $0.userId == userID } }
    func partner(of userID: ID) -> WalkSessionParticipant? { participants.first { $0.userId != userID } }
}

/// One shared, completed walk as it appears in *my* history. No GPS, no exact places.
struct CompletedWalk: Codable, Hashable, Sendable, Identifiable {
    var id: ID
    var title: String
    var startedAt: Date
    var durationSeconds: Int
    var distanceMeters: Int
    var fromLabel: String?
    var toLabel: String?
    var area: String?
    /// Present only when both people chose to reveal each other.
    var partnerName: String?
    var showOnProfile: Bool
    var revealPartner: Bool

    var route: String? {
        guard let fromLabel, let toLabel else { return area }
        return "\(fromLabel) → \(toLabel)"
    }
}

struct WalkStats: Codable, Hashable, Sendable {
    var walks: Int
    var distanceMeters: Int
    var durationSeconds: Int
    static let zero = WalkStats(walks: 0, distanceMeters: 0, durationSeconds: 0)
}

/// A transient live position. Sent over the private Realtime channel; never written to a table.
struct LivePosition: Codable, Hashable, Sendable {
    var userId: ID
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var heading: Double?
    /// Seconds since 1970, set on the sender's device when the GPS fix was taken.
    var timestamp: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var date: Date { Date(timeIntervalSince1970: timestamp) }
}

enum DistanceFormat {
    static func miles(_ meters: Double) -> String {
        let mi = meters / 1609.344
        return mi < 0.1 ? "\(Int((meters * 3.28084 / 10).rounded() * 10)) ft" : String(format: "%.1f mi", mi)
    }
    static func duration(_ seconds: Int) -> String {
        let m = (seconds + 30) / 60
        if m < 60 { return "\(max(m, 1)) min" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}
