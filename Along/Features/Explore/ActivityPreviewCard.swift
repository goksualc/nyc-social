import SwiftUI

/// The white sheet that rises over the map when a walk is selected: what it is, who's hosting, when and where, and one clear
/// next step. Everything is read from the real activity; nothing is invented (distance and time are route estimates).
struct ActivityPreviewCard: View {
    let activity: Activity
    let host: User?
    /// Accepted guests we're allowed to see (only the host and members see names; others get just a count).
    var guests: [User] = []
    let role: PlanRole?
    let isHost: Bool
    var route: RoutePreview?
    var now: Date = .now
    var isWorking = false
    let onPrimary: () -> Void
    let onOpen: () -> Void
    let onHost: () -> Void
    let onClose: () -> Void

    @GestureState private var drag: CGFloat = 0
    private var shape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous) }
    private var going: Int { activity.participantCount ?? activity.participantIDs.count }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(AlongColor.border).frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    topRow
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activity.title)
                            .font(AlongFont.walkDetailTitle).foregroundStyle(AlongColor.navy)
                            .lineLimit(3).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
                        Text(tagline).font(.system(.callout)).italic().foregroundStyle(AlongColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    infoRows
                }
                .padding(.horizontal, AlongSpacing.lg - 2)
                .padding(.bottom, AlongSpacing.sm)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.36)      // the rest of the screen stays map

            VStack(spacing: AlongSpacing.sm) {
                primaryButton
                hostRow
            }
            .padding(.horizontal, AlongSpacing.lg - 2)
            .padding(.top, AlongSpacing.xs)
            .padding(.bottom, AlongSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .background { shape.fill(AlongColor.white).ignoresSafeArea(edges: .bottom).shadow(color: .black.opacity(0.22), radius: 24, y: -4) }
        .offset(y: max(drag, 0) * 0.7)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { v, s, _ in s = v.translation.height }
                .onEnded { v in if v.translation.height > 90 { onClose() } }
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack(spacing: AlongSpacing.sm) {
            Image(systemName: "figure.walk")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(AlongColor.navy)
                .frame(width: 38, height: 38).background(AlongColor.lime.opacity(0.75), in: Circle())
            Text("Walk")
                .font(.system(.subheadline, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
            Spacer(minLength: 0)
            HStack(spacing: -12) {
                if let host { AlongProfileAvatar(user: host, size: 40) }
                ForEach(guests.prefix(2)) { AlongProfileAvatar(user: $0, size: 40) }
                let hidden = max(going - guests.prefix(2).count, 0)
                if hidden > 0 {
                    Text("+\(hidden)").font(.system(size: 13, weight: .bold)).foregroundStyle(AlongColor.navy)
                        .frame(width: 40, height: 40).background(AlongColor.lime.opacity(0.75), in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AlongColor.textTertiary)
                    .frame(width: 32, height: 32).background(AlongColor.surface, in: Circle())
                    .frame(width: AlongSize.minTouch, height: AlongSize.minTouch).contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
    }

    /// The host's note, or the brand line. (The "What's on your mind?" prompt gets its own row below.)
    private var tagline: String {
        let note = activity.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? "Walk together. Overthink together." : note
    }

    private var distanceText: String {
        let meters = route?.distance ?? activity.walk.from.coordinate.distance(to: activity.walk.to.coordinate) * 1.3
        let minutes = max(Int((route?.travelTime ?? meters / 1.35) / 60), 1)
        return "≈ \(DistanceFormat.miles(meters)), ~\(minutes) min"
    }

    private var infoRows: some View {
        VStack(spacing: 0) {
            row("person", "Hosted by \(host?.firstName ?? "someone")")
            divider
            row("point.topleft.down.to.point.bottomright.curvepath", "\(activity.walk.from.publicLabel) → \(activity.walk.to.publicLabel)")
            divider
            row("calendar", ActivityTime.summary(activity, now: now, separator: ", "))
            divider
            row("speedometer") {
                (Text("Pace: \(activity.walk.pace.rawValue)  ").foregroundStyle(AlongColor.textPrimary)
                 + Text(distanceText).font(.footnote).foregroundStyle(AlongColor.textTertiary))
            }
            divider
            row("person.2") {
                if activity.isFull { Text("Full").foregroundStyle(AlongColor.textTertiary) }
                else {
                    (Text("\(activity.spotsLeft) spot\(activity.spotsLeft == 1 ? "" : "s") left").fontWeight(.semibold).foregroundStyle(Color(hex: 0x3F7D1E))
                     + Text(going > 0 ? "  (\(going) going)" : "").foregroundStyle(AlongColor.textTertiary))
                }
            }
            if let prompt = activity.mindPrompt {
                divider
                row("bubble.left") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On their mind").font(.footnote).foregroundStyle(AlongColor.textTertiary)
                        Text(prompt).foregroundStyle(AlongColor.textPrimary)
                    }
                }
            }
        }
    }

    private var divider: some View { Rectangle().fill(AlongColor.border.opacity(0.8)).frame(height: 1).padding(.leading, 52) }

    private func row(_ symbol: String, _ text: String) -> some View {
        row(symbol) { Text(text).foregroundStyle(AlongColor.textPrimary) }
    }

    private func row<Content: View>(_ symbol: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: AlongSpacing.sm) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(AlongColor.navy.opacity(0.75))
                .frame(width: 38, height: 38).background(AlongColor.surface, in: Circle())
            content().font(.system(.body)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var hostRow: some View {
        Button(action: onHost) {
            HStack(spacing: AlongSpacing.sm) {
                if let host { AlongProfileAvatar(user: host, size: 44) }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hosted by").font(.footnote).foregroundStyle(AlongColor.textTertiary)
                    Text(host?.firstName ?? "Someone").font(.system(.headline, weight: .bold)).foregroundStyle(AlongColor.navy)
                }
                Spacer()
                Image(systemName: "person.crop.circle").font(.system(size: 18)).foregroundStyle(AlongColor.navy)
                    .frame(width: 44, height: 44).background(AlongColor.surface, in: Circle())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hosted by \(host?.firstName ?? "someone")")
        .accessibilityHint("Opens their profile")
    }

    @ViewBuilder private var primaryButton: some View {
        let live = activity.isActive(at: now)
        let (title, enabled): (String, Bool) = {
            if isHost || role == .host { return ("Manage Walk", true) }
            if !live { return ("Walk ended", false) }
            switch role {
            case .none: return (activity.isFull ? "Walk is full" : "Request to Join", !activity.isFull)
            case .pending: return ("Request Sent", false)
            case .accepted: return ("You're in", false)
            case .declined: return ("Request declined", false)
            case .host: return ("Manage Walk", true)
            }
        }()
        let canAct = enabled && role == nil || isHost || role == .host
        Button {
            Haptics.light()
            if isHost || role == .host { onOpen() } else { onPrimary() }
        } label: {
            HStack(spacing: 10) {
                if isWorking { ProgressView().tint(.white) }
                else {
                    if canAct { Image(systemName: "figure.walk") }
                    Text(title).font(.system(size: 18, weight: .semibold))
                    if canAct { Spacer(minLength: 0); Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)) }
                    else if role == .pending || role == .accepted { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)) }
                }
            }
            .foregroundStyle(canAct ? .white : AlongColor.textTertiary)
            .padding(.horizontal, AlongSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(canAct ? AlongColor.navy : AlongColor.surface, in: Capsule())
            .shadow(color: canAct ? AlongColor.navy.opacity(0.3) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(AlongPressStyle())
        .disabled(!canAct || isWorking)
        .accessibilityLabel(title)
    }
}
