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

    static let current: LaunchOptions = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        return LaunchOptions(skipOnboarding: args.contains("-along-skip-onboarding"), tab: value("-along-tab").flatMap(Int.init),
                             detent: value("-along-detent"), select: value("-along-select"), open: value("-along-open"),
                             create: value("-along-create"), conversation: value("-along-conversation"),
                             welcomeStep: value("-along-welcome-step"))
        #else
        return LaunchOptions()
        #endif
    }()
}
