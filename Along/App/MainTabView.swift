import SwiftUI

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationService.self) private var location
    @State private var selection = LaunchOptions.current.tab ?? 0
    @State private var chrome = TabChrome()
    @State private var showCreate = false

    /// Hidden while a walk card is open on the map, and while any conversation is open (its composer owns the bottom edge).
    private var barHidden: Bool { chrome.chatOpen || (chrome.isHidden && selection == 0) }

    var body: some View {
        // The system tab bar is hidden; a floating glass bar replaces it. Pages other than the map reserve room for it.
        TabView(selection: $selection) {
            ExploreView(store: store, location: location)
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
            PlansView(store: store)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: chrome.chatOpen ? 0 : 84) }
                .toolbar(.hidden, for: .tabBar)
                .tag(1)
            InboxView(store: store)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: chrome.chatOpen ? 0 : 84) }
                .toolbar(.hidden, for: .tabBar)
                .tag(2)
            ProfileView(store: store)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: chrome.chatOpen ? 0 : 84) }
                .toolbar(.hidden, for: .tabBar)
                .tag(3)
        }
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection, badge: store.pendingIncomingCount) { showCreate = true }
                .padding(.bottom, 6)
                .offset(y: barHidden ? 160 : 0)
                .opacity(barHidden ? 0 : 1)
                .allowsHitTesting(!barHidden)
                .alongAnimation(.smooth(duration: 0.3), value: barHidden)
        }
        .tint(AlongColor.navy)
        .environment(chrome)
        .environment(\.selectTab) { selection = $0 }
        .alongToasts()
        .onChange(of: selection) { Haptics.selection() }
        .sheet(isPresented: $showCreate) {
            CreateActivityFlow()
                .environment(store)
                .environment(\.avatarLoader, store.avatars)
                .alongToasts()
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
    }
}

private struct SelectTabKey: EnvironmentKey { static let defaultValue: (Int) -> Void = { _ in } }

extension EnvironmentValues {
    /// Lets deep views (e.g. an empty state) jump to another tab: 0 Explore, 1 Walks, 2 Messages, 3 Profile.
    var selectTab: (Int) -> Void {
        get { self[SelectTabKey.self] }
        set { self[SelectTabKey.self] = newValue }
    }
}
