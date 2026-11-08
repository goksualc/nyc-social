import SwiftUI

@main
struct AlongApp: App {
    @State private var session = AppSession.make()
    @State private var location = LocationService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var chromeStyle = ChromeStyle()

    init() { AlongAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(location)
                .environment(chromeStyle)
                // The brand palette is light-only, except the two dark first-launch tutorial pages (light status bar).
                .preferredColorScheme(chromeStyle.darkStatusBar ? .dark : .light)
                .task { await session.start() }
                .onOpenURL { url in Task { await session.handle(url: url) } }
                .onChange(of: scenePhase) { _, phase in Task { await session.store?.scenePhaseChanged(phase) } }
        }
    }
}

/// Lets a full-bleed dark screen ask for a light status bar without changing the app's light-only palette.
@MainActor @Observable
final class ChromeStyle {
    var darkStatusBar = false
}
