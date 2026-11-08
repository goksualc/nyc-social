import SwiftUI

/// Owns authentication state and the signed-in `AppStore`.
///
///     launching → (restore session) → signedOut | needsProfile | ready | failed
///
/// Live mode talks to Supabase; demo mode (no/invalid configuration) uses the in-memory backend so the
/// prototype still runs. Either way the rest of the app only sees `AppStore`.
@MainActor @Observable
final class AppSession {
    /// `launching` = loading, `signedOut` = unauthenticated, `ready` = authenticated, `failed` = error.
    enum Phase: Equatable { case launching, signedOut, emailVerification(String), passwordRecovery, needsProfile, ready, failed(String) }

    struct Services {
        var auth: any AuthService
        var backend: any AlongBackend
        var realtime: (any RealtimeService)?
        var live: (any LiveWalkService)?
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
    /// The person's first name, kept in memory to prefill the profile step.
    private(set) var suggestedName = ""

    private let services: Services
    private var activeUserID: ID?
    private var knownFullName: String?
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
                                   realtime: SupabaseRealtimeService(manager: manager),
                                   live: SupabaseLiveWalkService(manager: manager)),
                isLive: true, configProblem: nil)
        case .failure(let problem):
            return AppSession(services: Services(auth: DemoAuthService(), backend: MockAlongBackend(), realtime: nil, live: MockLiveWalkService()),
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

    /// Google, through Supabase OAuth. Cancelling the system sheet is not an error.
    func signInWithGoogle() async {
        await run {
            do {
                let session = try await self.services.auth.signInWithGoogle()
                await self.enter(session)
            } catch where ErrorPresenter.map(error) == .cancelled {
                return
            }
        }
    }

    func signInWithEmail(email: String, password: String) async {
        let email = AuthValidation.normalized(email)
        await run {
            do {
                let session = try await self.services.auth.signIn(email: email, password: password)
                await self.enter(session)
            } catch where ErrorPresenter.map(error) == .emailNotConfirmed {
                self.phase = .emailVerification(email)
            }
        }
    }

    func signUpWithEmail(fullName: String, email: String, password: String) async {
        let email = AuthValidation.normalized(email)
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let outcome = try await self.services.auth.signUp(email: email, password: password, fullName: name)
            self.knownFullName = name
            self.suggestedName = name.components(separatedBy: " ").first ?? name
            switch outcome {
            case .signedIn(let session): await self.enter(session)
            case .verificationRequired(let email): self.phase = .emailVerification(email)
            }
        }
    }

    /// Sends the confirmation link again. Returns whether it was sent.
    func resendVerification(email: String) async -> Bool {
        var sent = false
        await run { try await self.services.auth.resendVerification(email: email); sent = true }
        return sent
    }

    /// Always reports success unless the problem is local (offline, rate limit), so it never reveals whether an account exists.
    func requestPasswordReset(email: String) async -> Bool {
        var sent = false
        await run {
            do { try await self.services.auth.sendPasswordReset(email: AuthValidation.normalized(email)) }
            catch {
                let mapped = ErrorPresenter.map(error)
                if mapped == .offline || mapped == .tooManyAttempts { throw error }
            }
            sent = true
        }
        return sent
    }

    func updatePassword(_ newPassword: String) async {
        await run {
            try await self.services.auth.updatePassword(newPassword)
            guard let session = try await self.services.auth.restoreSession() else { throw AlongError.sessionExpired }
            self.activeUserID = nil
            await self.enter(session)
        }
    }

    /// Back to the welcome screen from the verification / recovery screens.
    func cancelPendingAuth() async {
        if phase == .passwordRecovery { await signOut() } else { reset(notice: nil) }
    }

    /// Completes a link opened from an email or the OAuth redirect.
    func handle(url: URL) async {
        guard isLive, AuthRedirect.kind(of: url) != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await services.auth.handleAuthLink(url)
            errorMessage = nil
            switch result.kind {
            case .recovery:
                activeUserID = result.session.userID
                phase = .passwordRecovery
            case .verify, .oauth:
                await enter(result.session)
            }
        } catch {
            let message = ErrorPresenter.message(for: error, fallback: AlongError.invalidLink.errorDescription ?? "")
            if phase == .signedOut { notice = message } else { errorMessage = message }
        }
    }

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
            try await self.services.backend.completeProfile(draft, fullName: self.knownFullName)
            await self.openStore()
            if let jpeg = draft.avatarJPEG, let store = self.store { _ = await store.setAvatar(jpeg: jpeg) }
        }
    }

    private func openStore() async {
        do {
            let store = try await AppStore.bootstrap(backend: services.backend, realtime: services.realtime)
            store.onSessionExpired = { [weak self] in self?.sessionExpired() }
            store.live = services.live
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
        guard phase == .ready || phase == .needsProfile || phase == .passwordRecovery else { return }
        reset(notice: AlongError.sessionExpired.errorDescription)
    }

    private func reset(notice: String?) {
        store = nil
        activeUserID = nil
        knownFullName = nil
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
