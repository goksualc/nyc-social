import SwiftUI
import AuthenticationServices
import CryptoKit

/// The single sign-in screen: Apple, Google or email. All three end in the same Supabase identity.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @State private var rawNonce = ""
    @State private var active: Provider?

    enum Provider { case apple, google }

    private var disabled: Bool { session.isBusy || !session.network.isOnline }

    var body: some View {
        VStack(spacing: 0) {
            AlongLogo(variant: .navy, width: 150)
                .padding(.top, AlongSpacing.xxl)
            Text("Good company, wherever you're headed.")
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(AlongColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AlongSpacing.xl)
                .padding(.horizontal, AlongSpacing.md)

            Spacer(minLength: AlongSpacing.xl)

            VStack(spacing: AlongSpacing.sm) {
                if let error = session.errorMessage { AuthMessage(text: error) }

                SignInWithAppleButton(.continue) { request in
                    rawNonce = AppleNonce.random()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleNonce.sha256(rawNonce)
                    session.clearError()
                    active = .apple
                } onCompletion: { result in
                    Task { await session.signInWithApple(result, rawNonce: rawNonce); active = nil }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: AlongSize.button)
                .clipShape(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                .overlay { if session.isBusy && active == .apple { ProgressView().tint(.white) } }
                .disabled(disabled)

                providerButton(background: AlongColor.white, foreground: AlongColor.textPrimary, border: AlongColor.border,
                               title: "Continue with Google", loading: session.isBusy && active == .google) {
                    Image("GoogleG").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                } action: {
                    session.clearError()
                    active = .google
                    Task { await session.signInWithGoogle(); active = nil }
                }

                NavigationLink(value: WelcomeView.Step.email) {
                    label(background: AlongColor.navy, foreground: .white, border: nil, title: "Continue with Email", loading: false) {
                        Image(systemName: "envelope").font(.system(size: 17, weight: .regular)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
                .simultaneousGesture(TapGesture().onEnded { session.clearError() })

                if !session.network.isOnline {
                    Text("You're offline. Connect to sign in.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }

                LegalText().padding(.top, AlongSpacing.xs)
            }
            .padding(.bottom, AlongSpacing.md)
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .alongScreenBackground()
    }

    private func providerButton<Icon: View>(background: Color, foreground: Color, border: Color?, title: String, loading: Bool,
                                            @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: {
            label(background: background, foreground: foreground, border: border, title: title, loading: loading, icon: icon)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !loading ? 0.5 : 1)
    }

    private func label<Icon: View>(background: Color, foreground: Color, border: Color?, title: String, loading: Bool,
                                   @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: AlongSpacing.xs) {
            if loading { ProgressView().tint(foreground) } else { icon() }
            Text(title).font(AlongFont.bodyEmphasis)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: AlongSize.button)
        .background(background, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
        .overlay { if let border { RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous).stroke(border, lineWidth: 1) } }
        .contentShape(Rectangle())
    }
}

/// "By continuing, you agree to …" — a name is a link only when a real page is configured.
struct LegalText: View {
    var body: some View {
        Text(text)
            .font(AlongFont.caption)
            .foregroundStyle(AlongColor.textTertiary)
            .multilineTextAlignment(.center)
            .tint(AlongColor.navy)
            .frame(maxWidth: .infinity)
    }

    private var text: AttributedString {
        var out = AttributedString("By continuing, you agree to our ")
        out += part("Terms of Service", LegalLinks.terms)
        out += AttributedString(" and ")
        out += part("Privacy Policy", LegalLinks.privacy)
        out += AttributedString(".")
        return out
    }

    private func part(_ name: String, _ url: URL?) -> AttributedString {
        var s = AttributedString(name)
        if let url { s.link = url; s.underlineStyle = .single }
        return s
    }
}

enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        precondition(SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
