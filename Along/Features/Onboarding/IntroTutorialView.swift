import SwiftUI

/// The first-launch introduction: a welcome, six short "how Along works" pages, and a closing screen. It is informational only:
/// no backend calls, no location, no real data. Both "Skip for Now" and "Find Your First Walk" end it by calling `onFinish`,
/// which hands over to the existing landing page.
struct IntroTutorialView: View {
    let onFinish: () -> Void
    @State private var page: Int
    @Environment(ChromeStyle.self) private var chrome: ChromeStyle?

    private static let last = 7
    private static let featureRange = 1...6

    init(startPage: Int = 0, onFinish: @escaping () -> Void) {
        _page = State(initialValue: min(max(startPage, 0), Self.last))
        self.onFinish = onFinish
    }

    private struct Feature {
        let title: String
        let text: String
        let hint: (symbol: String, text: String)?
        let points: [(symbol: String, text: String)]
    }

    private let features: [Feature] = [
        .init(title: "Your city,\nyour walks.", text: "Discover people walking around New York City. Every pin is a chance to meet someone new.",
              hint: ("hand.tap", "Tap a pin to explore walks. Swipe between cards when multiple walks are nearby."), points: []),
        .init(title: "Find your way.", text: "Search your route, pick a date, and find someone heading your way.",
              hint: ("magnifyingglass", "Try a route like “West Village → Bryant Park” to see relevant walks. Use Today, Tomorrow or the calendar to pick a day."), points: []),
        .init(title: "Make a move.", text: "Going for a walk? Post your route and let someone come along.", hint: nil,
              points: [("point.topleft.down.to.point.bottomright.curvepath", "Choose your route"), ("calendar", "Pick a date and time"),
                       ("figure.walk", "Set your pace and available spots"), ("bubble.left", "Share what's on your mind (optional)"),
                       ("eye.slash", "Keep your identity private with an anonymous walk")]),
        .init(title: "Walk with\nsomeone.", text: "Find a walk you like, send a request, and start a conversation.", hint: nil,
              points: [("paperplane", "Send a join request"), ("bell", "The host reviews your request"),
                       ("bubble.left", "The host can message you before accepting"), ("person.2", "Once accepted, you coordinate the walk together")]),
        .init(title: "Walk together,\nin real time.", text: "Once you're both ready, start your walk and follow each other on the map.", hint: nil,
              points: [("checkmark.circle", "Both confirm when you're ready"), ("mappin.and.ellipse", "See each other on the map while you walk"),
                       ("lock.shield", "Stop sharing your location any time")]),
        .init(title: "Every walk\nleaves a story.", text: "Keep track of your walks, discover shared interests, and reconnect with people you've met.", hint: nil,
              points: [("person.crop.circle", "Build your profile and share your interests"), ("chart.bar", "See your walking stats"),
                       ("arrow.triangle.2.circlepath", "Walk Again with people you've met")]),
    ]

    var body: some View {
        ZStack {
            TabView(selection: $page) {
                welcome.tag(0)
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in featurePage(f, index: i).tag(i + 1) }
                closing.tag(Self.last)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if Self.featureRange.contains(page) { topBar.transition(.opacity) }
        }
        .background(AlongColor.offWhite.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { if Self.featureRange.contains(page) { nextBar } }
        .alongAnimation(.smooth(duration: 0.3), value: page)
        // The welcome and closing pages are dark: give them a light status bar, and restore it on the way out.
        .onChange(of: page, initial: true) { _, p in chrome?.darkStatusBar = (p == 0 || p == Self.last) }
        .onDisappear { chrome?.darkStatusBar = false }
    }

    // MARK: Moving around

    private func go(_ delta: Int) {
        Haptics.selection()
        alongWithAnimation(.smooth(duration: 0.35)) { page = min(max(page + delta, 0), Self.last) }
    }

    // MARK: 0 · Welcome

    /// The deep navy behind the artwork on the two bookend screens.
    private static let night = Color(hex: 0x131832)
    private static let cream = AlongColor.offWhite

    /// Both bookend pages are laid out in fractions of the screen taken from the approved design, so every iPhone gets the same
    /// composition: (x, y) are fractions of the width and height.
    private var welcome: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack {
                Self.night
                // Tulip and carnations bleeding off the top-right corner.
                Image("IntroBouquet").resizable().scaledToFit().frame(width: W * 0.5586)
                    .position(x: W * 0.4426 + W * 0.5586 / 2, y: H * 0.0379 + W * 0.5586 * 600 / 448 / 2)
                    .accessibilityHidden(true)
                // The tile ornament rising from the bottom edge, its base running off the screen.
                Image("IntroOrnament").resizable().scaledToFit().frame(width: W)
                    .position(x: W / 2, y: H - W * 372 / 803 / 2 + W * 0.035).accessibilityHidden(true)

                AlongLogo(variant: .white, width: W * 0.285)
                    .position(x: W * 0.09 + W * 0.285 / 2, y: H * 0.150)
                AlongDisplayHeading("Welcome to\nAlong.", size: 46, color: Self.cream)
                    .frame(width: W * 0.8).position(x: W * 0.09 + W * 0.4, y: H * 0.336)
                Text("Walk together. Overthink together.").font(.system(.title3, design: .serif).italic()).foregroundStyle(Self.cream)
                    .minimumScaleFactor(0.8).lineLimit(1).frame(width: W * 0.84, alignment: .leading).position(x: W * 0.09 + W * 0.42, y: H * 0.451)
                Text("Your next NYC conversation is just a few steps away.").font(AlongFont.body).foregroundStyle(Self.cream.opacity(0.92))
                    .frame(width: W * 0.8, alignment: .leading).position(x: W * 0.09 + W * 0.4, y: H * 0.521)

                Button { go(1) } label: {
                    HStack { Text("Show Me Around").font(AlongFont.bodyEmphasis); Image(systemName: "arrow.right") }
                        .foregroundStyle(AlongColor.navy).frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(hex: 0xB5F36E), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).frame(width: W * 0.854).position(x: W / 2, y: H * 0.616)
                Button(action: onFinish) {
                    Text("Skip for Now").font(AlongFont.bodyEmphasis).foregroundStyle(Self.cream)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Self.cream.opacity(0.9), lineWidth: 1))
                }
                .buttonStyle(.plain).frame(width: W * 0.854).position(x: W / 2, y: H * 0.691)
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
    }

    // MARK: 1–6 · Features

    private var topBar: some View {
        VStack {
            HStack {
                Button { go(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: AlongSize.minTouch, height: AlongSize.minTouch).contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
                Spacer()
                HStack(spacing: 7) {
                    ForEach(Self.featureRange, id: \.self) { i in
                        Capsule().fill(i == page ? AlongColor.navy : AlongColor.navy.opacity(0.2))
                            .frame(width: i == page ? 18 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(page) of \(Self.featureRange.count)")
                Spacer()
                Button(action: onFinish) {
                    Text("Skip").font(AlongFont.subheadEmphasis).frame(minWidth: AlongSize.minTouch, minHeight: AlongSize.minTouch).contentShape(Rectangle())
                }
            }
            .foregroundStyle(AlongColor.navy)
            .padding(.horizontal, AlongSpacing.sm)
            Spacer()
        }
    }

    private var nextBar: some View {
        Button { go(1) } label: {
            HStack { Text("Next").font(AlongFont.bodyEmphasis); Image(systemName: "arrow.right") }
                .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: AlongSize.button)
                .background(AlongColor.navy, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AlongSpacing.gutter + 4).padding(.vertical, AlongSpacing.sm)
        .background(AlongColor.offWhite.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private func featurePage(_ f: Feature, index: Int) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AlongSpacing.md) {
                Text(f.title).font(AlongFont.screenHeading).foregroundStyle(AlongColor.navy)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text(f.text).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary).fixedSize(horizontal: false, vertical: true)
                preview(index)
                if let hint = f.hint {
                    HStack(alignment: .top, spacing: AlongSpacing.sm) {
                        Image(systemName: hint.symbol).font(.system(size: 22)).foregroundStyle(AlongColor.navy).frame(width: 30)
                        Text(hint.text).font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AlongSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                }
                if !f.points.isEmpty {
                    VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                        ForEach(Array(f.points.enumerated()), id: \.offset) { _, p in
                            HStack(alignment: .firstTextBaseline, spacing: AlongSpacing.sm) {
                                Image(systemName: p.symbol).font(.system(size: 16)).foregroundStyle(AlongColor.navy).frame(width: 26)
                                Text(p.text).font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, AlongSpacing.gutter + 4)
            .padding(.top, 64).padding(.bottom, AlongSpacing.lg)
        }
    }

    @ViewBuilder private func preview(_ index: Int) -> some View {
        switch index {
        case 0: IntroExplorePreview()
        case 1: IntroRoutePreview()
        case 2: IntroCreatePreview()
        case 3: IntroWalkCardPreview()
        case 4: IntroLiveWalkPreview()
        default: IntroMemoriesPreview()
        }
    }

    // MARK: 7 · Closing

    private var closing: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let frameW = W * 831 / 802
            ZStack {
                Self.night
                // The ornament and flower sprays that frame the page, top and bottom.
                Image("IntroFrameTop").resizable().scaledToFit().frame(width: frameW)
                    .position(x: W / 2, y: H * 0.068 + frameW * 412 / 831 / 2).accessibilityHidden(true)
                Image("IntroFrameBottom").resizable().scaledToFit().frame(width: frameW)
                    .position(x: W / 2, y: H * 0.811 + frameW * 315 / 831 / 2).accessibilityHidden(true)

                AlongMark(size: W * 0.18, color: Color(hex: 0xB5F36E)).position(x: W / 2, y: H * 0.309)
                AlongDisplayHeading("You're officially\nAlong.", size: 44, color: Self.cream, alignment: .center)
                    .frame(width: W * 0.86).position(x: W / 2, y: H * 0.453)
                Text("Your next conversation is just around the block.").font(.system(.title3, design: .serif))
                    .foregroundStyle(Self.cream).multilineTextAlignment(.center)
                    .frame(width: W * 0.7).position(x: W / 2, y: H * 0.575)
                Button(action: onFinish) {
                    HStack { Text("Find Your First Walk").font(AlongFont.bodyEmphasis); Image(systemName: "arrow.right") }
                        .foregroundStyle(AlongColor.navy).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(hex: 0xB5F36E), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).frame(width: W * 0.849).position(x: W / 2, y: H * 0.692)
                Button { go(-1) } label: { Text("Back").font(AlongFont.subheadEmphasis).foregroundStyle(Self.cream).frame(minWidth: 80, minHeight: AlongSize.minTouch) }
                    .position(x: W / 2, y: H * 0.778)
            }
            .frame(width: W, height: H)
        }
        .ignoresSafeArea()
    }
}

/// When the tutorial appears. A device-level flag, never per account: signing out, signing in as someone else or updating the
/// app can't bring it back.
enum IntroTutorialRules {
    static let key = "along.hasSeenIntroTutorial"
    /// Keys older builds already saved. If any is set this device is an established install and never sees the tutorial.
    static let legacyKeys = ["along.ageConfirmedLocally", "along.hasOnboarded"]

    static func isEstablishedInstall(_ defaults: UserDefaults) -> Bool { legacyKeys.contains { defaults.bool(forKey: $0) } }

    /// Only a signed-out launch, on a device that hasn't seen it, shows the tutorial.
    static func shouldShow(hasSeen: Bool, signedOut: Bool, established: Bool) -> Bool { signedOut && !hasSeen && !established }
}
