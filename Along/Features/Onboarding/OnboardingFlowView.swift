import SwiftUI
import PhotosUI

/// First-run profile setup after sign-in: basics → socials → interests → walking → location → done.
/// Minimal on purpose; everything except the name and the 18+ confirmation can be skipped.
struct OnboardingFlowView: View {
    @Environment(AppSession.self) private var session
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL
    @AppStorage("along.ageConfirmedLocally") private var ageConfirmedLocally = false

    private enum Step: Int, CaseIterable { case basics, socials, interests, walking, location, done }

    @State private var step: Step = .basics
    @State private var name = ""
    @State private var bio = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var confirmedAge = false
    @State private var photo: PhotosPickerItem?
    @State private var avatarJPEG: Data?
    @State private var instagram: String?
    @State private var xHandle: String?
    @State private var hobbies: [String] = []
    @State private var pace: PacePreference?
    @State private var duration: Int?
    @State private var neighborhoods: [String] = []
    @State private var didPrefill = false
    @State private var askedLocation = false

    private var canContinue: Bool {
        switch step {
        case .basics: !name.trimmingCharacters(in: .whitespaces).isEmpty && confirmedAge
        default: true
        }
    }

    private var latestBirthday: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                    switch step {
                    case .basics: basics
                    case .socials: socials
                    case .interests: interestsStep
                    case .walking: walking
                    case .location: locationStep
                    case .done: done
                    }
                    if let error = session.errorMessage {
                        Text(error).font(AlongFont.subhead).foregroundStyle(AlongColor.destructive)
                    }
                }
                .padding(.horizontal, AlongSpacing.gutter + 4)
                .padding(.top, AlongSpacing.md)
                .padding(.bottom, AlongSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .alongScreenBackground()
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            name = session.suggestedName
            confirmedAge = ageConfirmedLocally
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self) { avatarJPEG = EditProfileView.avatarJPEG(from: data) } }
        }
        .onChange(of: location.status) { _, _ in if step == .location, askedLocation { } }
        .alongAnimation(value: step)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if step != .basics {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? AlongColor.navy : AlongColor.border)
                        .frame(width: s == step ? 22 : 8, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, AlongSpacing.sm)
        .foregroundStyle(AlongColor.navy)
    }

    private var footer: some View {
        VStack(spacing: AlongSpacing.xs) {
            switch step {
            case .socials:
                AlongButton(title: "Continue") { go(1) }
                AlongButton(title: "Skip", style: .ghost) { instagram = nil; xHandle = nil; go(1) }
            case .location:
                if location.isAuthorized {
                    AlongButton(title: "Continue") { go(1) }
                } else if location.isDenied {
                    AlongButton(title: "Open Settings", style: .secondary) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    AlongButton(title: "Continue without location", style: .ghost) { go(1) }
                } else {
                    AlongButton(title: "Enable Location") { askedLocation = true; location.requestWhenInUse() }
                    AlongButton(title: "Not now", style: .ghost) { go(1) }
                }
            case .done:
                AlongButton(title: "Explore NYC", isLoading: session.isBusy) { Task { await finish() } }
            case .interests, .walking:
                AlongButton(title: "Continue") { go(1) }
                AlongButton(title: "Skip for now", style: .ghost) { go(1) }
            case .basics:
                AlongButton(title: "Continue") { go(1) }.disabled(!canContinue)
            }
        }
        .padding(.horizontal, AlongSpacing.gutter + 4)
        .padding(.vertical, AlongSpacing.sm)
        .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
    }

    private func go(_ delta: Int) {
        Haptics.selection()
        if let next = Step(rawValue: step.rawValue + delta) { alongWithAnimation { step = next } }
    }

    private func title(_ text: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlongDisplayHeading(text, size: 42)
            if let subtitle { Text(subtitle).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary) }
        }
    }

    // MARK: Steps

    private var basics: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            title("A little about you.", "Give your future walking buddies something to talk about.")
            HStack {
                Spacer()
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let avatarJPEG, let image = UIImage(data: avatarJPEG) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.fill").font(.system(size: 36)).foregroundStyle(AlongColor.navy.opacity(0.5))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(AlongColor.avatarTones[0])
                            }
                        }
                        .frame(width: 104, height: 104).clipShape(Circle())
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(AlongColor.navy, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                .accessibilityLabel(avatarJPEG == nil ? "Add a profile picture" : "Change profile picture")
                Spacer()
            }
            AlongTextField(label: "Display name", text: $name, prompt: "What should people call you?", limit: 24)
            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                Toggle("Add my birthday (optional)", isOn: $hasBirthday).tint(AlongColor.navy).font(AlongFont.body)
                if hasBirthday {
                    DatePicker("Birthday", selection: $birthday, in: ...latestBirthday, displayedComponents: .date)
                        .datePickerStyle(.compact).tint(AlongColor.navy)
                }
                Text("Only your age can ever be shown, and only if you choose to show it. Your birthday itself stays private.")
                    .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
            AlongTextField(label: "Short bio", text: $bio, prompt: "A line or two about you", axis: .vertical, lines: 1...3, limit: 120)
            Button { Haptics.selection(); confirmedAge.toggle() } label: {
                HStack(spacing: AlongSpacing.sm) {
                    Image(systemName: confirmedAge ? "checkmark.square.fill" : "square").font(.system(size: 24))
                        .foregroundStyle(confirmedAge ? AlongColor.navy : AlongColor.textSecondary)
                    Text("I confirm that I'm 18 or older.").font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: AlongSize.minTouch).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var socials: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            title("Find your people.", "Add your socials so your walking buddies can get to know you.")
            SocialUsernameField(network: .instagram, username: $instagram)
            SocialUsernameField(network: .x, username: $xHandle)
            Text("Optional. Along only links to your public profile. It never asks for a password and doesn't verify accounts.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            title("What are you into?")
            InterestsSelectionView(selection: $hobbies)
        }
    }

    private var walking: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            title("How do you like to walk?")
            WalkingPreferencesView(pace: $pace, duration: $duration, neighborhoods: $neighborhoods)
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            title("Let's explore New York City.",
                  "Along uses your location to discover nearby walks and share your position with an approved walking buddy during an active walk.")
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                point("eye.slash", "Your location is not publicly visible.")
                point("figure.walk", "Live sharing only begins during a walk you both explicitly start.")
                point("person.2", "Only approved participants can see each other's live location.")
                point("stop.circle", "Sharing stops when the walk ends, or when you stop it.")
            }
            if location.isAuthorized {
                Label("Location is on. Thank you.", systemImage: "checkmark.circle.fill").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
            } else if location.isDenied {
                Text("No problem. You can browse public walks without location. Joining a live walk needs it, and you can turn it on any time in Settings.")
                    .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AlongSpacing.md) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(AlongColor.navy).frame(width: 28)
            Text(text).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            Spacer(minLength: AlongSpacing.xl)
            AlongMark(size: 56)
            title("You're ready to walk Along.", "Walk together. Think out loud.")
        }
    }

    // MARK: Finish

    private func finish() async {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        await session.completeProfile(ProfileDraft(
            displayName: cleaned, bio: bio.trimmingCharacters(in: .whitespacesAndNewlines), confirmAge: confirmedAge,
            birthday: hasBirthday ? birthday : nil, instagram: instagram, xHandle: xHandle, hobbies: hobbies,
            pacePreference: pace, preferredDuration: duration, favoriteNeighborhoods: neighborhoods,
            avatarJPEG: avatarJPEG))
    }
}
