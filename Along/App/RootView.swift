import SwiftUI

/// Splash → (welcome → sign in → profile basics) → main app, driven entirely by `AppSession.phase`.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var splashDone = false
    /// Device-level: the tutorial is shown once, ever, to someone who opens Along signed out for the first time.
    @AppStorage(IntroTutorialRules.key) private var hasSeenIntro = false

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
        .onAppear { migrateExistingInstall() }
        // Anyone who gets as far as a session (restored at launch, or signed in later) has no need for the introduction.
        .onChange(of: session.phase) { _, phase in
            switch phase {
            case .launching, .signedOut, .failed: break
            default: hasSeenIntro = true
            }
        }
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

    private enum Screen: Equatable { case splash, intro, welcome, checkInbox, recovery, profile, main, failed }
    private var screen: Screen {
        guard splashDone else { return .splash }
        switch session.phase {
        case .launching: return .splash
        case .signedOut: return showsIntro ? .intro : .welcome
        case .emailVerification: return .checkInbox
        case .passwordRecovery: return .recovery
        case .needsProfile: return .profile
        case .ready: return session.store == nil ? .splash : .main
        case .failed: return .failed
        }
    }

    private var showsIntro: Bool {
        if LaunchOptions.current.intro != nil { return !introDismissed }
        return IntroTutorialRules.shouldShow(hasSeen: hasSeenIntro, signedOut: true, established: LaunchOptions.current.skipOnboarding)
    }
    @State private var introDismissed = false

    /// Saved before moving on, so closing the app right after "Skip for Now" can't bring the tutorial back.
    private func finishIntro() {
        hasSeenIntro = true
        introDismissed = true
    }

    /// Existing installs: if this device already got past the landing page or onboarded (older builds saved these), the
    /// tutorial is treated as seen, so established users are never surprised by it.
    private func migrateExistingInstall() {
        if IntroTutorialRules.isEstablishedInstall(.standard) { hasSeenIntro = true }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .splash: SplashView().transition(.opacity)
        case .intro:
            IntroTutorialView(startPage: LaunchOptions.current.intro ?? 0) { finishIntro() }.transition(.opacity)
        case .welcome: WelcomeView().transition(.opacity)
        case .checkInbox:
            if case .emailVerification(let email) = session.phase { CheckInboxView(email: email).transition(.opacity) }
        case .recovery: UpdatePasswordView().transition(.opacity)
        case .profile: OnboardingFlowView().transition(.opacity)
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
