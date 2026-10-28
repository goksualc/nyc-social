import SwiftUI

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var selection = LaunchOptions.current.tab ?? 0

    var body: some View {
        TabView(selection: $selection) {
            ExploreView(store: store, location: location)
                .tabItem { Label("Explore", systemImage: "map") }
                .tag(0)
            PlansView(store: store)
                .tabItem { Label("Plans", systemImage: "calendar") }
                .tag(1)
            InboxView(store: store)
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(store.pendingIncomingCount)
                .tag(2)
            ProfileView(store: store)
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(3)
        }
        .tint(AlongColor.navy)
        .environment(\.selectTab) { selection = $0 }
        .alongToasts()
        .onChange(of: selection) { Haptics.selection() }
    }
}

private struct SelectTabKey: EnvironmentKey { static let defaultValue: (Int) -> Void = { _ in } }

extension EnvironmentValues {
    /// Lets deep views (e.g. an empty state) jump to another tab: 0 Explore, 1 Plans, 2 Inbox, 3 Profile.
    var selectTab: (Int) -> Void {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }
}
