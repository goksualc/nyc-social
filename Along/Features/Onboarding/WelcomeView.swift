import SwiftUI

struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var path: [Step] = []

    enum Step: Hashable { case eligibility }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                AlongLogo(variant: .navy, width: 150)
                    .padding(.top, AlongSpacing.xxl)

                Spacer()

                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    Text("Good company, wherever you're headed.")
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(AlongColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.8)
                    Text("Find someone to walk or work alongside you.")
                        .font(.system(.title3))
                        .foregroundStyle(AlongColor.textTertiary)
                }

                Spacer()

                VStack(spacing: AlongSpacing.xs) {
                    AlongButton(title: "Get Started") { path.append(.eligibility) }
                    // Phase 1: "signing in" simply loads the local demo profile.
                    AlongButton(title: "I already have an account", style: .ghost, action: onFinish)
                }
                .padding(.bottom, AlongSpacing.md)
            }
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Step.self) { _ in
                EligibilityView(onContinue: onFinish)
            }
        }
    }
}

/// The one onboarding step: a self-declared 18+ confirmation and a few ground rules.
struct EligibilityView: View {
    let onContinue: () -> Void
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            Text("Before you join")
                .font(AlongFont.screenTitle)
                .foregroundStyle(AlongColor.textPrimary)
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

                Text("Prototype note: this is a self-declaration. A production release needs server-verified age checks.")
                    .font(AlongFont.caption)
                    .foregroundStyle(AlongColor.textTertiary)
            }
            .padding(.bottom, AlongSpacing.md)
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .alongScreenBackground()
        .navigationBarBackButtonHidden(false)
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
