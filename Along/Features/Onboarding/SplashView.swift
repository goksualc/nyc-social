import SwiftUI

/// Off-white screen, original navy logo, one gentle fade. Matches the system launch screen colour.
struct SplashView: View {
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AlongLogo(variant: .navy, width: 200)
            .opacity(visible ? 1 : 0)
            .onAppear {
                if reduceMotion { visible = true } else { withAnimation(.easeOut(duration: 0.9)) { visible = true } }
            }
    }
}
