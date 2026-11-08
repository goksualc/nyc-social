import Foundation

typealias ID = String

struct User: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var firstName: String
    var neighborhood: String = "New York City"
    var bio: String
    /// Hobbies from the catalogue plus any custom ones.
    var hobbies: [String]
    /// Index into the muted avatar tone list (also the fallback when a person has no photo).
    var avatarTone: Int = 0
    /// Path of the profile photo inside the private `avatars` Storage bucket, if any.
    var avatarPath: String?

    // Optional "about me" details. Nothing here is a street address.
    var age: Int?
    var occupation: String?
    var university: String?
    var languages: [String] = []
    var instagram: String?
    var xHandle: String?

    // Walking and conversation preferences.
    var pacePreference: PacePreference?
    var preferredDuration: Int?
    var favoriteNeighborhoods: [String] = []
    var discussionTopics: [ConversationTopic] = []
    var conversationCustom: [String] = []

    /// True for an organizer who stays anonymous. Such a user has no profile, photo or name to show.
    var isAnonymous = false

    var initial: String { String(firstName.prefix(1)).uppercased() }

    static let anonymousName = "Anonymous Walker"
    static let anonymousTagline = "Get to know each other over a walk."
    static let anonymousPrefix = "anon:"

    /// A stand-in for a hidden organizer. `id` is the server's opaque alias, never a real user id.
    static func anonymousHost(id: ID, interests: [String] = []) -> User {
        User(id: id, firstName: anonymousName, bio: "", hobbies: interests, avatarTone: 0, avatarPath: nil, isAnonymous: true)
    }
    static func isAlias(_ id: ID) -> Bool { id.hasPrefix(anonymousPrefix) }
    func handle(for network: SocialNetwork) -> String? { network == .instagram ? instagram : xHandle }
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
    /// Shows my completed-walk totals (never individual walks) on my public profile.
    var showWalkStats = false
    var showAge = false
    var notifyRequests = true
    var notifyMessages = true
    var notifyReminders = true
    /// Demo only: hosts respond to your requests automatically so the whole flow can be explored alone.
    var demoHostsRespond = true
}
