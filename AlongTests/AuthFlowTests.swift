import XCTest
import Supabase
@testable import Along

/// Scriptable auth backend: each call records itself and returns / throws what the test configured.
final class StubAuthService: AuthService, @unchecked Sendable {
    var stored: AuthSession?
    var signInResult: Result<AuthSession, Error> = .success(AuthSession(userID: "me"))
    var signUpResult: Result<SignUpOutcome, Error> = .success(.verificationRequired(email: "a@b.co"))
    var googleResult: Result<AuthSession, Error> = .success(AuthSession(userID: "me"))
    var linkResult: Result<AuthLinkResult, Error> = .failure(AlongError.invalidLink)
    var resetResult: Result<Void, Error> = .success(())
    private(set) var calls: [String] = []
    private(set) var signedOut = false

    func restoreSession() async throws -> AuthSession? { stored }
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession { try signInResult.get() }
    func signInWithGoogle() async throws -> AuthSession { calls.append("google"); return try googleResult.get() }
    func signIn(email: String, password: String) async throws -> AuthSession { calls.append("signIn:\(email)"); return try signInResult.get() }
    func signUp(email: String, password: String, fullName: String) async throws -> SignUpOutcome { calls.append("signUp:\(email)"); return try signUpResult.get() }
    func resendVerification(email: String) async throws { calls.append("resend:\(email)") }
    func sendPasswordReset(email: String) async throws { calls.append("reset:\(email)"); try resetResult.get() }
    func updatePassword(_ newPassword: String) async throws { calls.append("update") }
    func handleAuthLink(_ url: URL) async throws -> AuthLinkResult { try linkResult.get() }
    func signInDemo() async throws -> AuthSession { throw AlongError.notAllowed }
    func signOut() async throws { signedOut = true; stored = nil }
    func deleteAccount() async throws {}
    func sessionChanges() -> AsyncStream<AuthSession?> { AsyncStream { _ in } }
}

@MainActor
final class AuthFlowTests: XCTestCase {
    private func make(_ auth: StubAuthService) -> AppSession {
        AppSession(services: .init(auth: auth, backend: MockAlongBackend(), realtime: nil), isLive: true, configProblem: nil)
    }

    // MARK: Validation & links

    func testEmailValidation() {
        XCTAssertTrue(AuthValidation.isValidEmail(" Ana@Example.com "))
        for bad in ["", "ana", "ana@", "@x.com", "ana@x", "a b@x.com", "ana@x..com", "ana@.com"] {
            XCTAssertFalse(AuthValidation.isValidEmail(bad), bad)
        }
        XCTAssertEqual(AuthValidation.normalized(" Ana@Example.com "), "ana@example.com")
    }

    func testPasswordRule() {
        XCTAssertNotNil(AuthValidation.passwordProblem("short"))
        XCTAssertNil(AuthValidation.passwordProblem("long-enough"))
    }

    func testRedirectURLsAreRecognisedAndOthersIgnored() {
        for kind in [AuthRedirect.Kind.oauth, .verify, .recovery] {
            XCTAssertEqual(AuthRedirect.kind(of: AuthRedirect.url(kind)), kind)
            XCTAssertEqual(AuthRedirect.kind(of: URL(string: "com.along.app://auth/\(kind.rawValue)?code=abc")!), kind)
        }
        XCTAssertEqual(AuthRedirect.url(.oauth).absoluteString, "com.along.app://auth/oauth")
        XCTAssertNil(AuthRedirect.kind(of: URL(string: "evil://auth/verify")!))
        XCTAssertNil(AuthRedirect.kind(of: URL(string: "com.along.app://other/verify")!))
        XCTAssertNil(AuthRedirect.kind(of: URL(string: "com.along.app://auth/unknown")!))
    }

    func testAuthErrorMapping() {
        func api(_ code: ErrorCode) -> AuthError { .api(message: "x", errorCode: code, underlyingData: Data(), underlyingResponse: HTTPURLResponse()) }
        XCTAssertEqual(ErrorPresenter.map(api(.invalidCredentials)), .invalidCredentials)
        XCTAssertEqual(ErrorPresenter.map(api(.emailNotConfirmed)), .emailNotConfirmed)
        XCTAssertEqual(ErrorPresenter.map(api(.overEmailSendRateLimit)), .tooManyAttempts)
        XCTAssertEqual(ErrorPresenter.map(api(.otpExpired)), .invalidLink)
        XCTAssertEqual(ErrorPresenter.map(api(.providerDisabled)), .providerUnavailable)
        XCTAssertEqual(ErrorPresenter.map(api(.refreshTokenNotFound)), .sessionExpired)
        XCTAssertEqual(ErrorPresenter.map(AuthError.weakPassword(message: "x", reasons: [])), .weakPassword)
        XCTAssertEqual(ErrorPresenter.map(AuthError.pkceGrantCodeExchange(message: "x")), .invalidLink)
        XCTAssertEqual(ErrorPresenter.map(URLError(.notConnectedToInternet)), .offline)
        // Wrong-password text must not hint at whether the account exists.
        XCTAssertFalse(AlongError.invalidCredentials.errorDescription!.localizedCaseInsensitiveContains("no account"))
    }

    // MARK: Session state machine

    func testLaunchWithoutSessionIsSignedOut() async {
        let s = make(StubAuthService()); await s.start()
        XCTAssertEqual(s.phase, .signedOut)
    }

    func testLaunchWithStoredSessionOpensTheApp() async {
        let auth = StubAuthService(); auth.stored = AuthSession(userID: "me")
        let s = make(auth); await s.start()
        XCTAssertEqual(s.phase, .ready)
        XCTAssertNotNil(s.store)
    }

    func testEmailSignInEntersApp() async {
        let s = make(StubAuthService()); await s.start()
        await s.signInWithEmail(email: " Me@Along.app ", password: "password1")
        XCTAssertEqual(s.phase, .ready)
        XCTAssertNil(s.errorMessage)
    }

    func testWrongPasswordShowsFriendlyErrorAndStaysSignedOut() async {
        let auth = StubAuthService(); auth.signInResult = .failure(AlongError.invalidCredentials)
        let s = make(auth); await s.start()
        await s.signInWithEmail(email: "a@b.co", password: "nope")
        XCTAssertEqual(s.phase, .signedOut)
        XCTAssertEqual(s.errorMessage, AlongError.invalidCredentials.errorDescription)
    }

    func testUnconfirmedEmailRoutesToCheckInbox() async {
        let auth = StubAuthService(); auth.signInResult = .failure(AlongError.emailNotConfirmed)
        let s = make(auth); await s.start()
        await s.signInWithEmail(email: "A@B.co", password: "password1")
        XCTAssertEqual(s.phase, .emailVerification("a@b.co"))
    }

    func testSignUpWithConfirmationDoesNotAssumeASession() async {
        let s = make(StubAuthService()); await s.start()
        await s.signUpWithEmail(fullName: "Ana Lee", email: "a@b.co", password: "password1")
        XCTAssertEqual(s.phase, .emailVerification("a@b.co"))
        XCTAssertNil(s.store)
        XCTAssertEqual(s.suggestedName, "Ana")
    }

    func testVerificationLinkSignsInAndLeavesCheckInbox() async {
        let auth = StubAuthService()
        let s = make(auth); await s.start()
        await s.signUpWithEmail(fullName: "Ana", email: "a@b.co", password: "password1")
        auth.linkResult = .success(AuthLinkResult(kind: .verify, session: AuthSession(userID: "me")))
        await s.handle(url: AuthRedirect.url(.verify))
        XCTAssertEqual(s.phase, .ready)
    }

    func testInvalidOrForeignLinksAreHandledSafely() async {
        let auth = StubAuthService()
        let s = make(auth); await s.start()
        await s.handle(url: URL(string: "https://evil.example/auth/verify")!)      // ignored entirely
        XCTAssertEqual(s.phase, .signedOut); XCTAssertNil(s.notice)
        await s.handle(url: AuthRedirect.url(.recovery))                              // stub fails → expired link
        XCTAssertEqual(s.phase, .signedOut)
        XCTAssertEqual(s.notice, AlongError.invalidLink.errorDescription)
    }

    func testRecoveryLinkThenPasswordUpdateEntersApp() async {
        let auth = StubAuthService()
        let s = make(auth); await s.start()
        auth.linkResult = .success(AuthLinkResult(kind: .recovery, session: AuthSession(userID: "me")))
        auth.stored = AuthSession(userID: "me")
        await s.handle(url: AuthRedirect.url(.recovery))
        XCTAssertEqual(s.phase, .passwordRecovery)
        await s.updatePassword("brand-new-pass")
        XCTAssertTrue(auth.calls.contains("update"))
        XCTAssertEqual(s.phase, .ready)
    }

    func testPasswordResetNeverRevealsAccountExistence() async {
        let auth = StubAuthService()
        auth.resetResult = .failure(AlongError.notFound)           // e.g. unknown address
        let s = make(auth)
        let sent = await s.requestPasswordReset(email: "ghost@x.co")
        XCTAssertTrue(sent); XCTAssertNil(s.errorMessage)
        auth.resetResult = .failure(AlongError.offline)             // local problems are still reported
        let offline = await s.requestPasswordReset(email: "ghost@x.co")
        XCTAssertFalse(offline); XCTAssertNotNil(s.errorMessage)
    }

    func testCancellingGoogleIsSilent() async {
        let auth = StubAuthService(); auth.googleResult = .failure(AlongError.cancelled)
        let s = make(auth); await s.start()
        await s.signInWithGoogle()
        XCTAssertEqual(s.phase, .signedOut); XCTAssertNil(s.errorMessage)
    }

    func testGoogleSuccessEntersAppAndFailureShowsMessage() async {
        let auth = StubAuthService()
        let s = make(auth); await s.start()
        await s.signInWithGoogle()
        XCTAssertEqual(s.phase, .ready)
        let auth2 = StubAuthService(); auth2.googleResult = .failure(URLError(.notConnectedToInternet))
        let s2 = make(auth2); await s2.start()
        await s2.signInWithGoogle()
        XCTAssertEqual(s2.errorMessage, AlongError.offline.errorDescription)
    }

    func testSignOutClearsStoreAndAllowsAnotherAccount() async {
        let auth = StubAuthService()
        let s = make(auth); await s.start()
        await s.signInWithEmail(email: "a@b.co", password: "password1")
        XCTAssertNotNil(s.store)
        await s.signOut()
        XCTAssertNil(s.store); XCTAssertEqual(s.phase, .signedOut); XCTAssertTrue(auth.signedOut)
        await s.signInWithEmail(email: "c@d.co", password: "password1")
        XCTAssertEqual(s.phase, .ready)
    }
}
