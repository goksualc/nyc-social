import Foundation
import Supabase
import AuthenticationServices

/// Turns anything the stack can throw into a short, friendly sentence. Raw database or HTTP errors never reach the UI.
enum ErrorPresenter {
    /// Normalises transport, auth, Postgres and domain errors into `AlongError`.
    static func map(_ error: Error) -> AlongError {
        if let e = error as? AlongError { return e }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default: return .generic
            }
        }
        if let pg = error as? PostgrestError {
            if let known = AlongError(serverCode: pg.message) { return known }
            if pg.code == "PGRST301" || pg.message.localizedCaseInsensitiveContains("jwt") { return .sessionExpired }
            if pg.code == "42501" { return .notAllowed }             // insufficient_privilege / RLS
            if pg.code == "23505" { return .alreadyRequested }       // unique_violation
            return .generic
        }
        if let auth = error as? AuthError { return map(auth) }
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return .cancelled }
        if let storage = error as? StorageError {
            return storage.statusCode == "413" ? .imageTooLarge : .uploadFailed
        }
        if let http = error as? HTTPError, http.response.statusCode == 401 { return .sessionExpired }
        return .generic
    }

    /// Supabase Auth failures. Messages stay generic where specifics would reveal whether an account exists.
    static func map(_ error: AuthError) -> AlongError {
        switch error {
        case .weakPassword: return .weakPassword
        case .sessionMissing: return .sessionExpired
        case .pkceGrantCodeExchange, .implicitGrantRedirect: return .invalidLink
        case .api(_, let code, _, _):
            switch code {
            case .invalidCredentials: return .invalidCredentials
            case .emailNotConfirmed: return .emailNotConfirmed
            case .weakPassword: return .weakPassword
            case .samePassword: return .samePassword
            case .overRequestRateLimit, .overEmailSendRateLimit: return .tooManyAttempts
            case .providerDisabled, .oauthProviderNotSupported, .emailProviderDisabled: return .providerUnavailable
            case .flowStateNotFound, .flowStateExpired, .otpExpired, .badOAuthCallback, .badOAuthState, .badCodeVerifier: return .invalidLink
            case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed,
                 .badJWT, .invalidJWT, .noAuthorization, .userNotFound: return .sessionExpired
            default: return .generic
            }
        default: return .generic
        }
    }

    /// User-facing text. Specific, mapped problems ("full", "offline") win; otherwise the caller's contextual fallback.
    static func message(for error: Error, fallback: String) -> String {
        let mapped = map(error)
        switch mapped {
        case .generic, .uploadFailed: return fallback
        default: return mapped.errorDescription ?? fallback
        }
    }

    static func isSessionExpired(_ error: Error) -> Bool { map(error) == .sessionExpired }
}
