import Foundation

// MARK: - Hobbies

/// The curated hobby catalogue, grouped for the picker. Custom hobbies are free text stored next to these.
enum HobbyCatalog {
    struct Category: Identifiable, Hashable {
        let name: String
        let hobbies: [String]
        var id: String { name }
    }

    static let categories: [Category] = [
        .init(name: "Lifestyle", hobbies: ["Walking", "Coffee", "Cooking", "Baking", "Fashion", "Photography", "Traveling", "Exploring NYC"]),
        .init(name: "Arts & Culture", hobbies: ["Museums", "Art", "Music", "Concerts", "Movies", "Literature", "Architecture", "History"]),
        .init(name: "Sports & Outdoors", hobbies: ["Running", "Gym", "Pilates", "Yoga", "Hiking", "Cycling", "Tennis", "Kayaking"]),
        .init(name: "Technology & Career", hobbies: ["Technology", "Startups", "Entrepreneurship", "AI", "Crypto", "Design", "Finance", "Research"]),
        .init(name: "Social & Intellectual", hobbies: ["Philosophy", "Psychology", "Politics", "Science", "Current Events", "Deep Conversations", "Language Learning"]),
    ]

    static var all: [String] { categories.flatMap(\.hobbies) }
    static let maxSelected = 30
    static let maxCustomLength = 28

    /// Trimmed, single-spaced, capped. Returns nil for empty input.
    static func cleaned(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = String(words.prefix(maxCustomLength)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Walking preferences

enum PacePreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case slow = "Slow", casual = "Casual", moderate = "Moderate", fast = "Fast"
    var id: String { rawValue }
    var dbValue: String { rawValue.lowercased() }
    init?(dbValue: String) { self.init(rawValue: dbValue.prefix(1).uppercased() + dbValue.dropFirst()) }
}

enum WalkDuration {
    static let options = [15, 30, 45, 60]
    static func label(_ minutes: Int) -> String { minutes >= 60 ? "60+ min" : "\(minutes) min" }
}

enum Neighborhoods {
    static let options = ["Upper West Side", "Upper East Side", "Midtown", "Chelsea", "Flatiron", "Greenwich Village",
                          "East Village", "SoHo", "Financial District", "Harlem", "Lower East Side", "Williamsburg", "Park Slope",
                          "DUMBO", "Astoria", "Long Island City", "Flushing", "Riverdale", "St. George", "Other NYC"]
    static let maxSelected = 10
}

enum Languages {
    static let common = ["English", "Spanish", "Mandarin", "Cantonese", "French", "Hindi", "Arabic", "Portuguese", "Russian",
                         "Turkish", "German", "Italian", "Japanese", "Korean"]
    static let maxSelected = 8
}

// MARK: - Social accounts

/// Validates usernames (never passwords or tokens) and builds canonical profile URLs. Nothing here claims an account is verified.
enum SocialNetwork: String, CaseIterable, Sendable, Identifiable {
    case instagram, x
    var id: String { rawValue }
    var title: String { self == .instagram ? "Instagram" : "X" }
    var maxLength: Int { self == .instagram ? 30 : 15 }
    var hosts: [String] {
        self == .instagram ? ["instagram.com", "www.instagram.com", "instagr.am"] : ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]
    }

    /// Accepts "@name", "name" or a pasted profile URL; returns the bare username, or nil when it isn't valid.
    func username(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("/") || text.contains(".com") || text.contains("instagr.am") {
            let candidate = text.lowercased().hasPrefix("http") ? text : "https://" + text
            guard let url = URL(string: candidate), let host = url.host?.lowercased(), hosts.contains(host),
                  let first = url.pathComponents.dropFirst().first, first != "/" else { return nil }
            text = first
        }
        if text.hasPrefix("@") { text.removeFirst() }
        guard isValid(text) else { return nil }
        return text
    }

    func isValid(_ name: String) -> Bool {
        guard (1...maxLength).contains(name.count) else { return false }
        switch self {
        case .instagram:
            // letters, digits, dots, underscores; no leading/trailing/double dots (Instagram's own rules)
            guard name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }) else { return false }
            return !name.hasPrefix(".") && !name.hasSuffix(".") && !name.contains("..")
        case .x:
            return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        }
    }

    /// `https://instagram.com/<name>` / `https://x.com/<name>`. Only built from a validated username.
    func profileURL(for username: String) -> URL? {
        guard isValid(username) else { return nil }
        return URL(string: "https://\(self == .instagram ? "instagram.com" : "x.com")/\(username)")
    }
}
