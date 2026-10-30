import Foundation

/// Demo-mode stand-in for Supabase Auth: a single local profile, persisted with a UserDefaults flag.
final class DemoAuthService: AuthService, @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let key = "along.hasOnboarded"
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<AuthSession?>.Continuation] = [:]

    private var session: AuthSession { AuthSession(userID: "me") }

    func restoreSession() async throws -> AuthSession? {
        defaults.bool(forKey: key) || LaunchOptions.current.skipOnboarding ? session : nil
    }
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession { throw AlongError.notConfigured }
    func signInDemo() async throws -> AuthSession {
        defaults.set(true, forKey: key)
        emit(session)
        return session
    }
    func signOut() async throws {
        defaults.set(false, forKey: key)
        emit(nil)
    }
    func deleteAccount() async throws { try await signOut() }

    func sessionChanges() -> AsyncStream<AuthSession?> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.continuations[id] = nil } }
        }
    }

    private func emit(_ session: AuthSession?) {
        let all = lock.withLock { Array(continuations.values) }
        all.forEach { $0.yield(session) }
    }
}
