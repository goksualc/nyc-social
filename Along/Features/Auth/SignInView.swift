import SwiftUI

/// The single sign-in screen: Google or email. Both end in the same Supabase identity.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @State private var active: Provider?

    enum Provider { case google }

    private var disabled: Bool { session.isBusy || !session.network.isOnline }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: AlongSpacing.lg)

            VStack(spacing: AlongSpacing.md) {
                AlongDisplayHeading("Your next NYC\nconversation\nstarts here.", size: 40, alignment: .center)
                Text("Create your profile, find someone nearby,\nand take your thoughts for a walk.")
                    .font(AlongFont.body)
                    .foregroundStyle(AlongColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: AlongSpacing.xl)

            VStack(spacing: AlongSpacing.sm) {
                if let error = session.errorMessage { AuthMessage(text: error) }

                providerButton(background: AlongColor.white, foreground: AlongColor.textPrimary, border: AlongColor.border,
                               title: "Continue with Google", loading: session.isBusy && active == .google) {
                    Image("GoogleG").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                } action: {
                    session.clearError()
                    active = .google
                    Task { await session.signInWithGoogle(); active = nil }
                }

                // The primary action on this screen: create an account with email. (Google above also creates one.)
                NavigationLink(value: WelcomeView.Step.signUp) {
                    label(background: AlongColor.navy, foreground: .white, border: nil, title: "Create Account", loading: false) {
                        Image(systemName: "envelope").font(.system(size: 17, weight: .regular)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
                .simultaneousGesture(TapGesture().onEnded { session.clearError() })

                NavigationLink(value: WelcomeView.Step.email) {
                    (Text("Already have an account? ").foregroundStyle(AlongColor.textTertiary)
                     + Text("Sign in").foregroundStyle(AlongColor.navy).fontWeight(.semibold))
                        .font(AlongFont.subhead)
                        .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch)
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
            .fixedSize(horizontal: false, vertical: true)
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
