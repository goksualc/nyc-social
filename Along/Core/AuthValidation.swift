import Foundation

/// Client-side checks that make forms friendlier. The server remains the authority on passwords.
enum AuthValidation {
    /// Matches the project's minimum; Supabase may demand more (it replies with a weak-password error we surface).
    static let minimumPasswordLength = 8

    static func normalized(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func isValidEmail(_ raw: String) -> Bool {
        let email = normalized(raw)
        guard email.count <= 254, !email.contains(" ") else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64 else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty } && (domain.last?.count ?? 0) >= 2
    }

    static func passwordProblem(_ password: String) -> String? {
        password.count < minimumPasswordLength ? "Use at least \(minimumPasswordLength) characters." : nil
    }

    static func isValidName(_ raw: String) -> Bool { !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Terms / Privacy pages, supplied through build configuration. Left empty until real pages exist — nothing is invented.
enum LegalLinks {
    static var terms: URL? { url("LEGAL_TERMS_URL") }
    static var privacy: URL? { url("LEGAL_PRIVACY_URL") }

    private static func url(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String, raw.hasPrefix("https://"),
              let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }
}
