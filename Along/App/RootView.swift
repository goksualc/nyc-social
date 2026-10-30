import SwiftUI

/// Splash → (welcome → sign in → profile basics) → main app, driven entirely by `AppSession.phase`.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var splashDone = false

    var body: some View {
        ZStack {
            AlongColor.offWhite.ignoresSafeArea()
            content
        }
        .tint(AlongColor.navy)
        .overlay(alignment: .top) { OfflineBanner(isOnline: session.network.isOnline) }
        .task {
            try? await Task.sleep(for: .seconds(LaunchOptions.current.skipOnboarding ? 0.2 : 1.3))
            splashDone = true
        }
        .alongAnimation(.smooth(duration: 0.5), value: screen)
        .onChange(of: session.network.isOnline) { _, online in
            if online { Task { await session.store?.refresh(silent: true) } }     // catch up after reconnecting
        }
        .task(id: session.store != nil) {
            // Keep "expired plans leave the map" honest while the app stays open.
            guard let store = session.store else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                store.tick()
            }
        }
    }

    private enum Screen: Equatable { case splash, welcome, profile, main, failed }
    private var screen: Screen {
        guard splashDone else { return .splash }
        switch session.phase {
        case .launching: return .splash
        case .signedOut: return .welcome
        case .needsProfile: return .profile
        case .ready: return session.store == nil ? .splash : .main
        case .failed: return .failed
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .splash: SplashView().transition(.opacity)
        case .welcome: WelcomeView().transition(.opacity)
        case .profile: CompleteProfileView().transition(.opacity)
        case .main:
            if let store = session.store { MainTabView().environment(store).environment(\.avatarLoader, store.avatars).transition(.opacity) }
        case .failed:
            if case .failed(let message) = session.phase { LoadFailedView(message: message) }
        }
    }
}

struct LoadFailedView: View {
    let message: String
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: AlongSpacing.lg) {
            AlongLogo(variant: .navy, width: 120)
            AlongEmptyState(title: "Couldn't open Along.", message: message, actionTitle: "Try again") {
                Task { await session.retry() }
            }
            AlongButton(title: "Sign out", style: .ghost, fullWidth: false) { Task { await session.signOut() } }
        }
        .padding(AlongSpacing.gutter)
    }
}

/// A calm, slim notice when there's no connection.
struct OfflineBanner: View {
    let isOnline: Bool
    var body: some View {
        if !isOnline {
            Label("You're offline", systemImage: "wifi.slash")
                .font(AlongFont.label)
                .foregroundStyle(AlongColor.textPrimary)
                .padding(.horizontal, AlongSpacing.md).padding(.vertical, 6)
                .background(AlongColor.white, in: Capsule())
                .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
                .alongFloatingShadow()
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("You're offline")
        }
    }
}
