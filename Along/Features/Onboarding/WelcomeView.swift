import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("along.ageConfirmedLocally") private var ageConfirmedLocally = false
    @State private var path: [Step] = {
        switch LaunchOptions.current.welcomeStep {
        case "eligibility": [.eligibility]
        case "signin": [.signIn]
        case "email": [.signIn, .email]
        case "forgot": [.signIn, .email, .forgot]
        default: []
        }
    }()

    enum Step: Hashable { case eligibility, signIn, email, signUp, forgot }

    var body: some View {
        NavigationStack(path: $path) {
            landing
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .eligibility:
                    EligibilityView {
                        ageConfirmedLocally = true
                        if session.isLive { path.append(.signIn) } else { Task { await session.signInDemo() } }
                    }
                case .signIn: SignInView()
                case .email: EmailAuthView()
                case .signUp: EmailAuthView(initialMode: .signUp)
                case .forgot: ForgotPasswordView()
                }
            }
        }
    }
}

extension WelcomeView {
    /// The opening screen: logo, an Iznik-tile arch, the headline, and the two entry buttons. Everything between the logo and
    /// the buttons flexes, so it fits the smallest iPhone as well as a Pro Max without overlapping.
    @ViewBuilder var landing: some View {
        VStack(spacing: 0) {
            AlongLogo(variant: .navy, width: 136)
                .fixedSize(horizontal: false, vertical: true)       // never squeezed by the artwork below
                .layoutPriority(3)
                .padding(.top, AlongSpacing.sm)

            Spacer(minLength: AlongSpacing.sm)

            IznikArch()
                .aspectRatio(0.76, contentMode: .fit)
                .frame(maxWidth: 260, maxHeight: .infinity)
                .layoutPriority(1)

            Spacer(minLength: AlongSpacing.sm)

            VStack(spacing: AlongSpacing.sm) {
                AlongDisplayHeading("Walk a few blocks.\nOverthink together.",
                                    size: 32, alignment: .center)
                Text("Find someone nearby to walk with and talk about whatever's on your mind.")
                    .font(.system(.callout))
                    .foregroundStyle(AlongColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                if let notice = session.notice {
                    Text(notice).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary).multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: AlongSpacing.md)

            VStack(spacing: AlongSpacing.xs) {
                AlongButton(title: "Get Started") { path.append(.eligibility) }
                // Existing members skip the explainer; their 18+ confirmation is already on the server.
                AlongButton(title: "I already have an account", style: .ghost) {
                    if session.isLive { path.append(.signIn) } else { Task { await session.signInDemo() } }
                }
            }
            .padding(.bottom, AlongSpacing.xs)
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AlongColor.offWhite.ignoresSafeArea())
        .overlay(alignment: .topLeading) { IznikCorner().frame(width: 96).allowsHitTesting(false) }
        .overlay(alignment: .topTrailing) { IznikCorner(mirrored: true).frame(width: 96).allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom, spacing: 0) { IznikBand() }       // sits above the home indicator, below the buttons
    }
}

/// The one pre-sign-in step: a self-declared 18+ confirmation and a few ground rules.
struct EligibilityView: View {
    let onContinue: () -> Void
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            AlongDisplayHeading("Before you join.", size: 44)
                .padding(.top, AlongSpacing.lg)

            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                rule("person.2", "Along connects real people, so meet in public places.")
                rule("mappin.and.ellipse", "Exact meeting spots are only shared once a plan is accepted.")
                rule("hand.raised", "You can report or block anyone, any time.")
            }

            Spacer()

            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                Button {
                    Haptics.selection()
                    alongWithAnimation(.alongQuick) { confirmed.toggle() }
                } label: {
                    HStack(spacing: AlongSpacing.sm) {
                        Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24))
                            .foregroundStyle(confirmed ? AlongColor.navy : AlongColor.textSecondary)
                        Text("I confirm that I'm 18 or older.")
                            .font(AlongFont.body)
                            .foregroundStyle(AlongColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AlongSize.minTouch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(confirmed ? [.isButton, .isSelected] : .isButton)

                AlongButton(title: "Continue", action: onContinue).disabled(!confirmed)
            }
            .padding(.bottom, AlongSpacing.md)
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .alongScreenBackground()
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AlongSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(AlongColor.navy)
                .frame(width: 28)
            Text(text).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
        }
    }
}
