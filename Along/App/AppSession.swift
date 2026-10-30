import SwiftUI
import AuthenticationServices

/// Owns authentication state and the signed-in `AppStore`.
///
///     launching → (restore session) → signedOut | needsProfile | ready | failed
///
/// Live mode talks to Supabase; demo mode (no/invalid configuration) uses the in-memory backend so the
/// prototype still runs. Either way the rest of the app only sees `AppStore`.
@MainActor @Observable
final class AppSession {
    enum Phase: Equatable { case launching, signedOut, needsProfile, ready, failed(String) }

    struct Services {
        var auth: any AuthService
        var backend: any AlongBackend
        var realtime: (any RealtimeService)?
    }

    let isLive: Bool
    /// Why we're in demo mode (nil when live).
    let configProblem: SupabaseConfig.Problem?
    let network = NetworkMonitor()

    private(set) var phase: Phase = .launching
    private(set) var store: AppStore?
    /// One-line message shown on the welcome screen (e.g. after a session expires).
    private(set) var notice: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Apple only shares the user's name on first sign-in; kept in memory to prefill the profile step.
    private(set) var suggestedName = ""

    private let services: Services
    private var activeUserID: ID?
    private var fullNameFromApple: String?
    private var observer: Task<Void, Never>?

    init(services: Services, isLive: Bool, configProblem: SupabaseConfig.Problem?) {
        self.services = services
        self.isLive = isLive
        self.configProblem = configProblem
    }

    /// Chooses live or demo from the build configuration.
    static func make() -> AppSession {
        switch SupabaseConfig.load() {
        case .success(let config):
            let manager = SupabaseManager(config: config)
            return AppSession(
                services: Services(auth: SupabaseAuthService(manager: manager), backend: SupabaseBackend(manager: manager),
                                   realtime: SupabaseRealtimeService(manager: manager)),
                isLive: true, configProblem: nil)
        case .failure(let problem):
            return AppSession(services: Services(auth: DemoAuthService(), backend: MockAlongBackend(), realtime: nil),
                              isLive: false, configProblem: problem)
        }
    }

    // MARK: Launch

    func start() async {
        guard observer == nil else { return }
        // Only *sign-outs* are driven by the stream; sign-ins are handled where they happen, so nothing runs twice.
        observer = Task { [weak self] in
            guard let changes = self?.services.auth.sessionChanges() else { return }
            for await session in changes where session == nil { self?.handleSignedOutElsewhere() }
        }
        do {
            if let session = try await services.auth.restoreSession() { await enter(session) } else { phase = .signedOut }
        } catch {
            phase = .signedOut
        }
    }

    // MARK: Sign in

    func signInDemo() async {
        await run {
            let session = try await self.services.auth.signInDemo()
            await self.enter(session)
        }
    }

    /// Completes Sign in with Apple. `rawNonce` is the unhashed nonce whose SHA-256 was sent in the request.
    func signInWithApple(_ result: Result<ASAuthorization, Error>, rawNonce: String) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Couldn't sign in with Apple. Try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Couldn't sign in with Apple. Try again."
                return
            }
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespaces)
                if !formatted.isEmpty { fullNameFromApple = formatted; suggestedName = name.givenName ?? formatted }
            }
            await run {
                let session = try await self.services.auth.signInWithApple(idToken: idToken, nonce: rawNonce)
                await self.enter(session)
            }
        }
    }

    /// Loads the profile and either asks for the basics or opens the app.
    private func enter(_ session: AuthSession) async {
        guard activeUserID != session.userID || phase != .ready else { return }
        do {
            let profile = try await services.backend.loadMyProfile()
            activeUserID = session.userID
            if !profile.isComplete {
                if suggestedName.isEmpty { suggestedName = profile.fullName?.components(separatedBy: " ").first ?? "" }
                phase = .needsProfile
            } else {
                await openStore()
            }
        } catch {
            if ErrorPresenter.isSessionExpired(error) { sessionExpired() }
            else { phase = .failed(ErrorPresenter.message(for: error, fallback: "Couldn't load your profile. Try again.")) }
        }
    }

    func completeProfile(_ draft: ProfileDraft) async {
        await run {
            try await self.services.backend.completeProfile(draft, fullName: self.fullNameFromApple)
            await self.openStore()
        }
    }

    private func openStore() async {
        do {
            let store = try await AppStore.bootstrap(backend: services.backend, realtime: services.realtime)
            store.onSessionExpired = { [weak self] in self?.sessionExpired() }
            self.store = store
            phase = .ready
            await store.startRealtime()
        } catch {
            phase = .failed(ErrorPresenter.message(for: error, fallback: "Couldn't load Along. Try again."))
        }
    }

    func retry() async {
        phase = .launching
        if let session = try? await services.auth.restoreSession() { activeUserID = nil; await enter(session) } else { phase = .signedOut }
    }

    // MARK: Sign out / delete / expiry

    func signOut() async {
        await store?.stopRealtime()
        try? await services.auth.signOut()
        reset(notice: nil)
    }

    /// Deletes the account and all its data, then returns to the welcome screen.
    func deleteAccount() async {
        await run {
            await self.store?.prepareForAccountDeletion()
            try await self.services.auth.deleteAccount()
            self.reset(notice: "Your account was deleted.")
        }
    }

    func sessionExpired() {
        guard phase != .signedOut else { return }
        Task { await store?.stopRealtime(); try? await services.auth.signOut() }
        reset(notice: AlongError.sessionExpired.errorDescription)
    }

    private func handleSignedOutElsewhere() {
        guard phase == .ready || phase == .needsProfile else { return }
        reset(notice: AlongError.sessionExpired.errorDescription)
    }

    private func reset(notice: String?) {
        store = nil
        activeUserID = nil
        fullNameFromApple = nil
        suggestedName = ""
        self.notice = notice
        phase = .signedOut
    }

    func clearError() { errorMessage = nil }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch {
            errorMessage = ErrorPresenter.message(for: error, fallback: "Something went wrong. Try again.")
        }
    }
}
