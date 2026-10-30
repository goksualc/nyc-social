import Foundation
import Supabase

/// JSON coding shared by every Supabase call: snake_case keys ⇄ camelCase properties, Postgres timestamps.
enum SupabaseCoding {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// Postgres emits microseconds ("…05.123456+00:00"); trim to milliseconds so ISO8601DateFormatter accepts it.
    static func parse(_ raw: String) -> Date? {
        var s = raw
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let digitsEnd = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            let digits = s[afterDot..<digitsEnd]
            if digits.count > 3 { s.replaceSubrange(afterDot..<digitsEnd, with: digits.prefix(3)) }
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }

    static func format(_ date: Date) -> String { withFraction.string(from: date) }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
            }
            return date
        }
        return d
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer(); try c.encode(format(date))
        }
        return e
    }
}

/// Owns the single `SupabaseClient`. Created once at launch when configuration is valid.
final class SupabaseManager: @unchecked Sendable {
    let client: SupabaseClient
    let config: SupabaseConfig
    let decoder = SupabaseCoding.makeDecoder()
    /// Integration tests authenticate with a pre-minted JWT (no Auth server), so the user id is supplied directly.
    private let userIDOverride: ID?

    init(config: SupabaseConfig, userIDOverride: ID? = nil) {
        self.config = config
        self.userIDOverride = userIDOverride
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                db: .init(encoder: SupabaseCoding.makeEncoder(), decoder: SupabaseCoding.makeDecoder()),
                auth: .init(emitLocalSessionAsInitialSession: true)))
    }

    /// The signed-in user's id in the canonical lowercase form the database returns.
    var currentUserID: ID? { userIDOverride ?? client.auth.currentUser?.id.uuidString.lowercased() }

    func requireUserID() throws -> ID {
        guard let id = currentUserID else { throw AlongError.sessionExpired }
        return id
    }
}

/// Local-only settings (notifications, location preference) live on the device; `profileVisibility` lives in `profiles`.
struct LocalSettingsStore {
    private let defaults = UserDefaults.standard
    private func key(_ uid: ID) -> String { "along.settings.\(uid)" }

    func load(for uid: ID) -> UserSettings {
        guard let data = defaults.data(forKey: key(uid)), let s = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            var s = UserSettings(); s.demoHostsRespond = false; return s
        }
        return s
    }
    func save(_ settings: UserSettings, for uid: ID) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key(uid)) }
    }
    func clear(for uid: ID) { defaults.removeObject(forKey: key(uid)) }
}
