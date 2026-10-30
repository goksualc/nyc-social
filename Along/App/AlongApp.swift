import SwiftUI

@main
struct AlongApp: App {
    @State private var session = AppSession.make()
    @State private var location = LocationService()
    @Environment(\.scenePhase) private var scenePhase

    init() { AlongAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(location)
                .preferredColorScheme(.light)   // the brand palette is light-only
                .task { await session.start() }
                .onChange(of: scenePhase) { _, phase in Task { await session.store?.scenePhaseChanged(phase) } }
        }
    }
}
