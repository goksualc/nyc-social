import SwiftUI

/// Splash → welcome → (18+ check) → main app. The splash stays up until the store has loaded.
struct RootView: View {
    let store: AppStore?
    @AppStorage("along.hasOnboarded") private var hasOnboarded = false
    @State private var phase: Phase = .splash
    @State private var splashElapsed = false

    enum Phase { case splash, welcome, main }

    var body: some View {
        ZStack {
            AlongColor.offWhite.ignoresSafeArea()
            switch phase {
            case .splash:
                SplashView().transition(.opacity)
            case .welcome:
                WelcomeView(onFinish: { hasOnboarded = true; go(.main) }).transition(.opacity)
            case .main:
                if let store { MainTabView().environment(store).transition(.opacity) }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(LaunchOptions.current.skipOnboarding ? 0.2 : 1.3))
            splashElapsed = true
        }
        // Both triggers are onChange so they always read the current `store` (a .task closure would hold a stale copy).
        .onChange(of: splashElapsed) { advanceIfReady() }
        .onChange(of: store != nil) { advanceIfReady() }
        .task(id: store != nil) {
            // Keep "expired plans leave the map" honest while the app stays open.
            guard let store else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                store.tick()
            }
        }
    }

    private func advanceIfReady() {
        guard phase == .splash, splashElapsed, store != nil else { return }
        go(hasOnboarded || LaunchOptions.current.skipOnboarding ? .main : .welcome)
    }

    private func go(_ next: Phase) {
        alongWithAnimation(.smooth(duration: 0.5)) { phase = next }
    }
}
