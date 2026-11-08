import SwiftUI
import MapKit

/// "Your walk is coming up!" → "Ready to walk?". Both people must press "I'm Ready"; the server starts the walk once.
struct WalkReadyView: View {
    @Bindable var vm: LiveWalkViewModel
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL
    let onClose: () -> Void

    private var iAmReady: Bool { vm.myParticipant?.isReady ?? false }
    private var partnerReady: Bool { vm.partnerParticipant?.isReady ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                Text(vm.partnerParticipant?.joinedAt != nil ? "Ready to walk?" : "Your walk is coming up!")
                    .font(AlongFont.walkScreenHeading).foregroundStyle(AlongColor.textPrimary)
                if let a = vm.activity { details(a) }
                participants
                if let message = vm.errorMessage {
                    Text(message).font(AlongFont.subhead).foregroundStyle(AlongColor.destructive)
                }
                locationNote
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.top, AlongSpacing.sm)
            .padding(.bottom, AlongSpacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { action }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }.accessibilityLabel("Close")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            Text(a.title).font(AlongRoboto.bold(24, relativeTo: .title2)).foregroundStyle(AlongColor.textPrimary)
            AlongInfoRow(symbol: "clock", text: ActivityTime.summary(a, now: vm.store.now))
            AlongInfoRow(symbol: "mappin.circle", text: a.walk.from.publicLabel,
                         secondary: a.meetingDetails.isEmpty ? nil : a.meetingDetails)
            AlongInfoRow(symbol: "arrow.triangle.turn.up.right.diamond", text: "to \(a.walk.to.publicLabel)")
            if let route = vm.route {
                Map(initialPosition: .rect(ActivityDetailViewModel.rect(for: route.coordinates)), interactionModes: []) {
                    MapPolyline(coordinates: route.coordinates.map(\.cl)).stroke(AlongColor.navy, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    Annotation("Start", coordinate: a.walk.from.coordinate.cl, anchor: .center) {
                        Circle().fill(AlongColor.navy).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                    Annotation("End", coordinate: a.walk.to.coordinate.cl, anchor: .center) { AlongRouteEndDot() }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                .allowsHitTesting(false)
                Text(route.summary + (route.isEstimate ? " · approximate" : "")).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            AlongSectionLabel("Walking together")
            HStack(spacing: AlongSpacing.md) {
                person(vm.me, name: "You", ready: iAmReady)
                person(vm.partner, name: vm.partner?.firstName ?? "Your buddy", ready: partnerReady)
            }
        }
    }

    private func person(_ user: User?, name: String, ready: Bool) -> some View {
        HStack(spacing: AlongSpacing.sm) {
            if let user { AlongProfileAvatar(user: user, size: 48) }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                Label(ready ? "Ready" : "Not yet", systemImage: ready ? "checkmark.circle.fill" : "circle")
                    .font(AlongFont.caption).foregroundStyle(ready ? AlongColor.navy : AlongColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(AlongSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var locationNote: some View {
        if location.isDenied {
            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                Label("Location is off", systemImage: "location.slash").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                Text("Walking together on the map needs your location, and only during this walk. You can turn it on in Settings.")
                    .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                AlongButton(title: "Open Settings", style: .secondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            .padding(AlongSpacing.md).frame(maxWidth: .infinity, alignment: .leading).alongCard()
        } else {
            Label("Your location is shared with \(vm.partner?.firstName ?? "your buddy") only, only while the walk is live. You can stop sharing at any time.",
                  systemImage: "lock")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
    }

    @ViewBuilder private var action: some View {
        VStack(spacing: AlongSpacing.xs) {
            if iAmReady {
                HStack(spacing: AlongSpacing.sm) {
                    ProgressView()
                    Text("Waiting for \(vm.partner?.firstName ?? "your walking buddy")...").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: AlongSize.button)
                .background(AlongColor.surface, in: Capsule())
            } else if location.canAskForPermission {
                AlongButton(title: "Allow Location to Start") { location.requestWhenInUse() }
            } else {
                AlongButton(title: "I'm Ready", isLoading: vm.isBusy) { Task { await vm.imReady() } }
                    .disabled(location.isDenied)
            }
        }
        .padding(.horizontal, AlongSpacing.gutter)
        .padding(.vertical, AlongSpacing.sm)
        .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
    }
}
