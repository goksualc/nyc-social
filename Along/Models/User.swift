import Foundation

typealias ID = String

enum Interest: String, CaseIterable, Codable, Sendable, Identifiable {
    case tech = "Tech", coffee = "Coffee", startups = "Startups", fitness = "Fitness"
    case art = "Art", design = "Design", books = "Books", walking = "Walking"
    var id: String { rawValue }
    /// Value stored in `profiles.interests`.
    var dbValue: String { rawValue.lowercased() }
    init?(dbValue: String) { self.init(rawValue: dbValue.prefix(1).uppercased() + dbValue.dropFirst()) }
}

enum AlongPurpose: String, CaseIterable, Codable, Sendable, Identifiable {
    case walkingBuddies = "Walking buddies"
    case coworkingCompany = "Coworking company"
    var id: String { rawValue }
    /// Value stored in `profiles.looking_for`.
    var dbValue: String { self == .walkingBuddies ? "walking_buddies" : "coworking_company" }
    init?(dbValue: String) {
        switch dbValue {
        case "walking_buddies": self = .walkingBuddies
        case "coworking_company": self = .coworkingCompany
        default: return nil
        }
    }
}

struct User: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var firstName: String
    var neighborhood: String = "Manhattan, NYC"
    var bio: String
    var interests: [Interest]
    var alongFor: Set<AlongPurpose>
    /// Index into the muted avatar tone list (also the fallback when a person has no photo).
    var avatarTone: Int = 0
    /// Path of the profile photo inside the private `avatars` Storage bucket, if any.
    var avatarPath: String?

    var initial: String { String(firstName.prefix(1)).uppercased() }
}

enum ProfileVisibility: String, CaseIterable, Codable, Sendable, Identifiable {
    case everyone = "Everyone on Along"
    case activityMembers = "Only people in my plans"
    var id: String { rawValue }
    var dbValue: String { self == .everyone ? "everyone" : "activity_members" }
    init(dbValue: String) { self = dbValue == "activity_members" ? .activityMembers : .everyone }
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
