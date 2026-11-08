import Foundation

enum AlongError: LocalizedError, Sendable, Equatable {
    case outsideNYC, startInPast, invalidTimes, sameLocation, invalidRoute
    case notFound, notAllowed, blocked, chatClosed
    case activityFull, alreadyRequested, requestDeclined, activityClosed, capacityBelowAccepted
    case notAuthenticated, sessionExpired, profileIncomplete, ageRequired
    case offline, imageTooLarge, uploadFailed, notConfigured
    case rateLimited, cancelled, generic
    // Walk sessions
    case sessionRequiresTwo, noParticipant, sessionClosed
    /// The database is missing something this version of the app needs (a migration hasn't been applied).
    case backendOutOfDate
    // Authentication
    case invalidCredentials, emailNotConfirmed, weakPassword, samePassword, invalidLink, tooManyAttempts, providerUnavailable, signInFailed

    /// Maps the short codes raised by the database functions (`raise exception 'activity_full'`).
    init?(serverCode: String) {
        switch serverCode.trimmingCharacters(in: .whitespaces) {
        case "outside_manhattan", "outside_nyc": self = .outsideNYC
        case "start_in_past": self = .startInPast
        case "invalid_times", "too_far_ahead": self = .invalidTimes
        case "same_location": self = .sameLocation
        case "invalid_route": self = .invalidRoute
        case "not_found": self = .notFound
        case "not_allowed": self = .notAllowed
        case "blocked": self = .blocked
        case "activity_full": self = .activityFull
        case "already_requested": self = .alreadyRequested
        case "request_declined": self = .requestDeclined
        case "activity_closed", "request_not_pending": self = .activityClosed
        case "capacity_below_accepted": self = .capacityBelowAccepted
        case "own_activity": self = .notAllowed
        case "not_authenticated": self = .sessionExpired
        case "profile_incomplete": self = .profileIncomplete
        case "age_required": self = .ageRequired
        case "rate_limited": self = .rateLimited
        case "session_requires_two": self = .sessionRequiresTwo
        case "no_participant": self = .noParticipant
        case "session_closed": self = .sessionClosed
        default: return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .outsideNYC: "Along covers New York City. Pick a place in one of the five boroughs."
        case .startInPast: "Pick a time in the future."
        case .invalidTimes: "The end time needs to be after the start."
        case .sameLocation: "Start and destination can't be the same."
        case .invalidRoute: "That route doesn't look right. Try different places."
        case .notFound: "That plan is no longer available."
        case .notAllowed: "You can't do that."
        case .blocked: "That's not available."
        case .chatClosed: "This conversation is closed."
        case .activityFull: "This plan is already full."
        case .alreadyRequested: "You've already asked to join."
        case .requestDeclined: "The host declined your earlier request."
        case .activityClosed: "This plan has ended or was cancelled."
        case .capacityBelowAccepted: "You already have more guests than that."
        case .notAuthenticated, .sessionExpired: "Your session expired. Please sign in again."
        case .profileIncomplete: "Finish your profile to continue."
        case .ageRequired: "You need to confirm you're 18 or older."
        case .offline: "You're offline. Check your connection and try again."
        case .imageTooLarge: "That photo is too large. Try a smaller one."
        case .uploadFailed: "Couldn't upload your photo. Try again."
        case .notConfigured: "Along isn't connected to a backend yet."
        case .rateLimited: "Too many reports today. Try again tomorrow."
        case .invalidCredentials: "That email and password don't match. Try again."
        case .emailNotConfirmed: "Confirm your email first. We can send the link again."
        case .weakPassword: "Choose a stronger password. Use at least 8 characters and avoid common passwords."
        case .samePassword: "Choose a password you haven't used before."
        case .invalidLink: "That link has expired or was already used. Request a new one."
        case .tooManyAttempts: "Too many attempts. Wait a minute and try again."
        case .providerUnavailable: "This sign-in option isn't available right now. Try another way."
        case .signInFailed: "Couldn't sign you in. Try again."
        case .sessionRequiresTwo: "Live walks are for two people for now. Keep just one walking buddy accepted."
        case .noParticipant: "Accept a walking buddy first."
        case .sessionClosed: "This walk has already finished."
        case .backendOutOfDate: "Along's server needs its latest update before this works. Apply the newest database migrations."
        case .cancelled: nil
        case .generic: "Something went wrong. Try again."
        }
    }
}
