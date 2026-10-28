import SwiftUI

@main
struct AlongApp: App {
    @State private var store: AppStore?
    @State private var location = LocationService()

    init() { AlongAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environment(location)
                .preferredColorScheme(.light)   // the brand palette is light-only in Phase 1
                .task { store = await AppStore.bootstrap() }
        }
    }
}
