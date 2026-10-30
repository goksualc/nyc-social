import Foundation

/// Public client configuration, injected into Info.plist from `Config/Secrets.xcconfig` (git-ignored).
/// Only the project URL and the *publishable* key ever ship in the app. A secret / service-role key is rejected.
struct SupabaseConfig: Equatable, Sendable {
    let url: URL
    let publishableKey: String

    enum Problem: Error, Equatable {
        case missing
        case invalidURL
        case secretKeyDetected
    }

    static func load(from bundle: Bundle = .main) -> Result<SupabaseConfig, Problem> {
        validate(url: bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                 key: bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String)
    }

    static func validate(url rawURL: String?, key rawKey: String?) -> Result<SupabaseConfig, Problem> {
        let urlString = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func isUnset(_ s: String) -> Bool {
            s.isEmpty || s.hasPrefix("$(") || s.uppercased().contains("YOUR-PROJECT") || s.uppercased().contains("YOUR_KEY")
        }
        guard !isUnset(urlString), !isUnset(key) else { return .failure(.missing) }

        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else { return .failure(.invalidURL) }
        let isLocal = ["localhost", "127.0.0.1"].contains(host)
        guard url.scheme == "https" || (isLocal && url.scheme == "http") else { return .failure(.invalidURL) }

        if key.hasPrefix("sb_secret_") || jwtRole(key) == "service_role" { return .failure(.secretKeyDetected) }
        return .success(SupabaseConfig(url: url, publishableKey: key))
    }

    /// Reads the `role` claim of a legacy JWT-style key without verifying it (just to refuse service-role keys).
    private static func jwtRole(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["role"] as? String
    }
}

extension SupabaseConfig.Problem {
    /// Developer-facing explanation shown in the About screen and logs (never a credential).
    var explanation: String {
        switch self {
        case .missing: "No Supabase configuration. Copy Config/Secrets.xcconfig.example to Config/Secrets.xcconfig and fill it in."
        case .invalidURL: "SUPABASE_URL isn't a valid https URL."
        case .secretKeyDetected: "A secret / service-role key was found in the app configuration. Use the publishable key instead."
        }
    }
}
