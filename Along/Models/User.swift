import Foundation

typealias ID = String

enum Interest: String, CaseIterable, Codable, Sendable, Identifiable {
    case tech = "Tech", coffee = "Coffee", startups = "Startups", fitness = "Fitness"
    case art = "Art", design = "Design", books = "Books", walking = "Walking"
    var id: String { rawValue }
}

enum AlongPurpose: String, CaseIterable, Codable, Sendable, Identifiable {
    case walkingBuddies = "Walking buddies"
    case coworkingCompany = "Coworking company"
    var id: String { rawValue }
}

struct User: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var firstName: String
    var neighborhood: String = "Manhattan, NYC"
    var bio: String
    var interests: [Interest]
    var alongFor: Set<AlongPurpose>
    /// Index into the muted avatar tone list. Real photos arrive with the backend.
    var avatarTone: Int = 0

    var initial: String { String(firstName.prefix(1)).uppercased() }
}

enum ProfileVisibility: String, CaseIterable, Codable, Sendable, Identifiable {
    case everyone = "Everyone on Along"
    case activityMembers = "Only people in my plans"
    var id: String { rawValue }
}

/// Settings are intentionally split: *who can see my profile* is independent of *how my location is used*.
struct UserSettings: Codable, Hashable, Sendable {
    var profileVisibility: ProfileVisibility = .everyone
    var useLocationToCenterMap = true
    var notifyRequests = true
    var notifyMessages = true
    var notifyReminders = true
    /// Demo only: hosts respond to your requests automatically so the whole flow can be explored alone.
    var demoHostsRespond = true
}
