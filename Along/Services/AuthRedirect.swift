import Foundation

/// The app's auth callback URLs. The scheme is the bundle identifier, so it is unique to Along.
/// Every URL below must be listed under Supabase → Authentication → URL Configuration → Redirect URLs.
enum AuthRedirect {
    static let scheme = "com.along.app"
    static let host = "auth"

    enum Kind: String, Equatable { case oauth, verify, recovery }

    static func url(_ kind: Kind) -> URL { URL(string: "\(scheme)://\(host)/\(kind.rawValue)")! }

    /// Which Along auth callback `url` is, or nil for anything else (other schemes, hosts or paths are ignored).
    static func kind(of url: URL) -> Kind? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
        return Kind(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
