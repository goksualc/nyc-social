import Foundation

/// Debug-only launch arguments for jumping straight to a screen (screenshots, UI work).
/// e.g. `-along-skip-onboarding -along-tab 1 -along-open act-midtown`
struct LaunchOptions {
    var skipOnboarding = false
    var tab: Int?
    var detent: String?
    var select: String?
    var open: String?
    var create: String?
    var conversation: String?
    var welcomeStep: String?
    var live = false
    var inboxFilter: String?
    var onboarding = false
    var readyAll = false
    /// Opens the first numbered cluster's cards on the map (debug screenshots).
    var cluster = false
    /// Forces the first-launch tutorial (optionally at a page) without touching the saved flag.
    var intro: Int?

    static let current: LaunchOptions = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        return LaunchOptions(skipOnboarding: args.contains("-along-skip-onboarding"), tab: value("-along-tab").flatMap(Int.init),
                             detent: value("-along-detent"), select: value("-along-select"), open: value("-along-open"),
                             create: value("-along-create"), conversation: value("-along-conversation"),
                             welcomeStep: value("-along-welcome-step"), live: args.contains("-along-live"), inboxFilter: value("-along-inbox"),
                             onboarding: args.contains("-along-onboarding"), readyAll: args.contains("-along-ready"), cluster: args.contains("-along-cluster"),
                             intro: args.contains("-along-intro") ? (value("-along-intro-page").flatMap(Int.init) ?? 0) : nil)
        #else
        return LaunchOptions()
        #endif
    }()
}
