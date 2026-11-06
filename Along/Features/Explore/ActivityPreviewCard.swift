import SwiftUI
import CoreLocation

/// The large rounded card that rises over the map when a marker is selected (walks first, cowork adapted).
/// Compact by default: title, host, key facts, route and the join button. Drag up or tap the handle for the vibe,
/// the host's note, the host and nearby plans. Drag down to collapse, then dismiss.
struct ActivityPreviewCard: View {
    let activity: Activity
    let host: User?
    let role: PlanRole?
    let isHost: Bool
    var distance: String? = nil
    let nearby: [Activity]
    var now: Date = .now
    var isWorking = false
    @Binding var expanded: Bool
    let onPrimary: () -> Void
    let onOpen: () -> Void
    let onHost: () -> Void
    let onSelect: (Activity) -> Void
    let onClose: () -> Void

    @AppStorage("along.savedPlans") private var savedRaw = ""
    @GestureState private var drag: CGFloat = 0
    @State private var bodyHeight: CGFloat = 400
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 20, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            topRow
            title
            routeLines
            if !activity.note.isEmpty {
                Text(activity.note).font(AlongFont.body).foregroundStyle(AlongColor.textTertiary)
                    .lineLimit(expanded ? nil : 2).fixedSize(horizontal: false, vertical: true)
            }
            infoRow
            Text(ActivityTime.summary(activity, now: now, separator: " · "))
                .font(AlongFont.body).foregroundStyle(AlongColor.textPrimary).padding(.top, 2)
            if expanded {
                ScrollView(showsIndicators: false) { expandedBody }
                    .frame(height: min(bodyHeight, UIScreen.main.bounds.height * 0.3))
                    .scrollBounceBehavior(.basedOnSize)
            }
            primaryButton.frame(maxWidth: .infinity).padding(.top, AlongSpacing.xs)
        }
        .padding(.horizontal, AlongSpacing.lg - 4)
        .padding(.top, AlongSpacing.md)
        .padding(.bottom, AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlongColor.white, in: shape)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 4)
        .overlay(alignment: .topLeading) { spotsBadge.offset(x: -8, y: -50) }
        .offset(y: max(drag, 0) * 0.6)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { v, s, _ in s = v.translation.height }
                .onEnded { v in
                    if v.translation.height < -40 { alongWithAnimation { expanded = true } }
                    else if v.translation.height > 60 { if expanded { alongWithAnimation { expanded = false } } else { onClose() } }
                }
        )
        .alongAnimation(value: expanded)
        .accessibilityElement(children: .contain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            detailRows
            if !nearby.isEmpty { nearbySection }
            ShareLink(item: "\(activity.title) — \(ActivityTime.summary(activity, now: now, separator: ", ")) · \(activity.publicLocationLabel). Join me on Along.") {
                Label("Share this plan", systemImage: "square.and.arrow.up").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
    }

    // MARK: Compact layout (matches the map-card reference)

    /// Heart (saved on this device) with the distance underneath, top right.
    private var topRow: some View {
        HStack(alignment: .top) {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button { Haptics.selection(); toggleSaved() } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart").font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSaved ? AlongColor.navy : AlongColor.textSecondary)
                        .frame(width: AlongSize.minTouch, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(isSaved ? "Remove from saved" : "Save plan")
                if let distance { Text(distance).font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary) }
            }
        }
        .frame(minHeight: 30)
    }

    private var title: some View {
        Button(action: onOpen) {
            Text(activity.title)
                .font(.system(.title3, design: .serif, weight: .semibold)).underline()
                .foregroundStyle(AlongColor.navy).multilineTextAlignment(.leading)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain).accessibilityHint("Opens plan details")
    }

    private var routeLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch activity.details {
            case .walk(let w):
                Text("\(w.from.publicLabel) → \(w.to.publicLabel)")
                Text(w.from.area)
            case .cowork(let c):
                Text(c.venue.name)
                Text(c.venue.area)
            }
        }
        .font(.system(.title3, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// ⓘ  Pace · Hosted by … — tap to show or hide the full details.
    private var infoRow: some View {
        Button { toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 20)).foregroundStyle(AlongColor.navy)
                Text(activity.walk.map { "\($0.pace.rawValue) pace" } ?? activity.detailLabel)
                    .font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                if let host { Text("· \(host.firstName)").font(AlongFont.body).foregroundStyle(AlongColor.textTertiary) }
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AlongColor.textSecondary)
            }
            .frame(minHeight: AlongSize.minTouch).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Hide details" : "Show details")
    }

    private var savedIDs: Set<String> { Set(savedRaw.split(separator: ",").map(String.init)) }
    private var isSaved: Bool { savedIDs.contains("\(activity.id)") }
    private func toggleSaved() {
        var ids = savedIDs
        if isSaved { ids.remove("\(activity.id)") } else { ids.insert("\(activity.id)") }
        savedRaw = ids.sorted().joined(separator: ",")
    }

    private func toggle() { Haptics.selection(); alongWithAnimation { expanded.toggle() } }

    /// Navy disc attached to the card's top-left corner: how many spots are left.
    private var spotsBadge: some View {
        VStack(spacing: 0) {
            Text(activity.isFull ? "Full" : "\(activity.spotsLeft)")
                .font(.system(size: activity.isFull ? 18 : 26, weight: .bold, design: .rounded))
            Text(activity.isFull ? "NO SPOTS" : (activity.spotsLeft == 1 ? "SPOT LEFT" : "SPOTS LEFT"))
                .font(.system(size: 8, weight: .bold)).tracking(0.3)
        }
        .foregroundStyle(.white)
        .frame(width: 76, height: 76)
        .background(AlongColor.navy, in: Circle())
        .rotationEffect(.degrees(-12))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.spotsLabel)
    }

    // MARK: Rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            switch activity.details {
            case .walk(let w):
                row("figure.walk", "Vibe", "\(w.pace.rawValue) pace, side by side")
            case .cowork(let c):
                row("laptopcomputer", "Style", c.style.cardLabel)
            }
            do {
                if !activity.note.isEmpty { rowDivider; row("text.quote", "About", activity.note) }
                if let host {
                    rowDivider
                    Button(action: onHost) {
                        row("person.crop.circle", "Host", host.interests.isEmpty ? host.firstName
                            : "\(host.firstName) · \(host.interests.prefix(3).map(\.rawValue).joined(separator: ", "))", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the host's profile")
                }
            }
        }
        .padding(.horizontal, AlongSpacing.sm + 2)
        .background(AlongColor.offWhite, in: RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
    }

    private var rowDivider: some View { AlongDivider() }

    private func row(_ symbol: String, _ label: String, _ value: String, chevron: Bool = false) -> some View {
        HStack(alignment: .top, spacing: AlongSpacing.sm) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(AlongColor.navy)
                .frame(width: 32, height: 32).background(AlongColor.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(.caption2, weight: .semibold)).tracking(0.8).foregroundStyle(AlongColor.textSecondary)
                Text(value).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textSecondary).padding(.top, 10) }
        }
        .padding(.vertical, AlongSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            AlongSectionLabel("Nearby")
            ForEach(nearby) { other in
                Button { onSelect(other) } label: {
                    HStack(spacing: AlongSpacing.sm) {
                        Image(systemName: other.kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(AlongColor.navy)
                            .frame(width: 34, height: 34).background(AlongColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(other.title).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary).lineLimit(1)
                            Text("\(ActivityTime.summary(other, now: now, separator: ", ")) · \(distance(to: other))")
                                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AlongSize.minTouch + 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private var primaryButton: some View {
        let live = activity.isActive(at: now)
        let (title, enabled): (String, Bool) = {
            if isHost || role == .host { return ("Manage Plan", true) }
            if !live { return ("Plan ended", false) }
            switch role {
            case .none: return (activity.isFull ? "Plan is full" : "Request to Join", !activity.isFull)
            case .pending: return ("Request Sent", false)
            case .accepted: return ("You're in", false)
            case .declined: return ("Request declined", false)
            case .host: return ("Manage Plan", true)
            }
        }()
        let canAct = enabled && role == nil || isHost || role == .host
        Button {
            Haptics.light()
            if isHost || role == .host { onOpen() } else { onPrimary() }
        } label: {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) }
                else { Text(title.uppercased()).font(.system(size: 15, weight: .semibold)).tracking(0.8) }
            }
            .foregroundStyle(canAct ? .white : AlongColor.textTertiary)
            .padding(.horizontal, AlongSpacing.xl)
            .frame(minWidth: 230, minHeight: 48)
            .background(canAct ? AlongColor.navy : AlongColor.surface, in: Capsule())
        }
        .buttonStyle(AlongPressStyle())
        .disabled(!(canAct) || isWorking)
        .accessibilityLabel(title)
    }

    // MARK: Helpers

    private func fact(_ symbol: String, _ text: String, emphasised: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(AlongFont.label)
        }
        .foregroundStyle(emphasised ? AlongColor.navy : AlongColor.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(AlongColor.surface, in: Capsule())
    }

    private func iconLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(AlongColor.navy)
            .frame(width: AlongSize.button, height: AlongSize.button)
            .overlay(Circle().stroke(AlongColor.border, lineWidth: 1))
            .contentShape(Circle())
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: { iconLabel(symbol) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func distance(to other: Activity) -> String {
        let m = CLLocation(latitude: activity.mapCoordinate.latitude, longitude: activity.mapCoordinate.longitude)
            .distance(from: CLLocation(latitude: other.mapCoordinate.latitude, longitude: other.mapCoordinate.longitude))
        return m < 1000 ? "\(Int((m / 10).rounded() * 10)) m" : String(format: "%.1f km", m / 1000)
    }
}
