import SwiftUI
import AuthenticationServices
import CryptoKit

struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("along.ageConfirmedLocally") private var ageConfirmedLocally = false
    @State private var path: [Step] = {
        switch LaunchOptions.current.welcomeStep { case "eligibility": [.eligibility]; case "signin": [.signIn]; default: [] }
    }()

    enum Step: Hashable { case eligibility, signIn }

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
                    if let notice = session.notice {
                        Text(notice).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                    }
                }

                Spacer()

                VStack(spacing: AlongSpacing.xs) {
                    AlongButton(title: "Get Started") { path.append(.eligibility) }
                    // Existing members skip the explainer; their 18+ confirmation is already on the server.
                    AlongButton(title: "I already have an account", style: .ghost) {
                        if session.isLive { path.append(.signIn) } else { Task { await session.signInDemo() } }
                    }
                }
                .padding(.bottom, AlongSpacing.md)
            }
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .eligibility:
                    EligibilityView {
                        ageConfirmedLocally = true
                        if session.isLive { path.append(.signIn) } else { Task { await session.signInDemo() } }
                    }
                case .signIn:
                    SignInView()
                }
            }
        }
    }
}

/// The one pre-sign-in step: a self-declared 18+ confirmation and a few ground rules.
struct EligibilityView: View {
    let onContinue: () -> Void
    @State private var confirmed = false

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

/// Native Sign in with Apple. A fresh random nonce is sent hashed to Apple and raw to Supabase for verification.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @State private var rawNonce = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            Text("Sign in")
                .font(AlongFont.screenTitle)
                .foregroundStyle(AlongColor.textPrimary)
                .padding(.top, AlongSpacing.lg)
            Text("We use Sign in with Apple, so there's no new password to remember. You choose what other people see.")
                .font(AlongFont.body)
                .foregroundStyle(AlongColor.textTertiary)

            Spacer()

            VStack(spacing: AlongSpacing.sm) {
                if let error = session.errorMessage {
                    Text(error).font(AlongFont.subhead).foregroundStyle(AlongColor.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SignInWithAppleButton(.continue) { request in
                    rawNonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(rawNonce)
                    session.clearError()
                } onCompletion: { result in
                    Task { await session.signInWithApple(result, rawNonce: rawNonce) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: AlongSize.button)
                .clipShape(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                .disabled(session.isBusy || !session.network.isOnline)
                .overlay { if session.isBusy { ProgressView().tint(.white) } }

                if !session.network.isOnline {
                    Text("You're offline. Connect to sign in.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
            }
            .padding(.bottom, AlongSpacing.md)
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .alongScreenBackground()
    }

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        precondition(SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// First-run basics after the first sign-in: name, optional bio, interests, and the 18+ confirmation.
struct CompleteProfileView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("along.ageConfirmedLocally") private var ageConfirmedLocally = false
    @State private var name = ""
    @State private var bio = ""
    @State private var interests: Set<Interest> = []
    @State private var purposes: Set<AlongPurpose> = [.walkingBuddies, .coworkingCompany]
    @State private var confirmedAge = false
    @State private var didPrefill = false

    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && confirmedAge }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                Text("A little about you")
                    .font(AlongFont.screenTitle)
                    .foregroundStyle(AlongColor.textPrimary)
                    .padding(.top, AlongSpacing.lg)

                AlongTextField(label: "First name", text: $name, prompt: "What should people call you?", limit: 24)
                AlongTextField(label: "Bio", text: $bio, prompt: "Optional", axis: .vertical, lines: 1...3, limit: 120)

                VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                    AlongSectionLabel("Interests")
                    FlowLayout(spacing: 8) {
                        ForEach(Interest.allCases) { interest in
                            Button {
                                Haptics.selection()
                                if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
                            } label: {
                                AlongChip(title: interest.rawValue, isSelected: interests.contains(interest)).frame(minHeight: AlongSize.minTouch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                    AlongSectionLabel("Along for")
                    FlowLayout(spacing: 8) {
                        ForEach(AlongPurpose.allCases) { purpose in
                            Button {
                                Haptics.selection()
                                if purposes.contains(purpose) { if purposes.count > 1 { purposes.remove(purpose) } } else { purposes.insert(purpose) }
                            } label: {
                                AlongChip(title: purpose.rawValue, isSelected: purposes.contains(purpose),
                                          symbol: purpose == .walkingBuddies ? "figure.walk" : "laptopcomputer")
                                    .frame(minHeight: AlongSize.minTouch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    Haptics.selection()
                    confirmedAge.toggle()
                } label: {
                    HStack(spacing: AlongSpacing.sm) {
                        Image(systemName: confirmedAge ? "checkmark.square.fill" : "square")
                            .font(.system(size: 24))
                            .foregroundStyle(confirmedAge ? AlongColor.navy : AlongColor.textSecondary)
                        Text("I confirm that I'm 18 or older.").font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AlongSize.minTouch)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let error = session.errorMessage {
                    Text(error).font(AlongFont.subhead).foregroundStyle(AlongColor.destructive)
                }
            }
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .padding(.bottom, AlongSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .alongScreenBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AlongButton(title: "Continue", isLoading: session.isBusy) {
                Task {
                    await session.completeProfile(ProfileDraft(
                        displayName: name.trimmingCharacters(in: .whitespaces), bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                        interests: Interest.allCases.filter(interests.contains), alongFor: purposes, confirmAge: confirmedAge))
                }
            }
            .disabled(!canContinue)
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .padding(.vertical, AlongSpacing.sm)
            .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            name = session.suggestedName
            confirmedAge = ageConfirmedLocally
        }
    }
}
