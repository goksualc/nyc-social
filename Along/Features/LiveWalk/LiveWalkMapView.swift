import SwiftUI
import MapKit

/// A walker on the live map: their photo in a ring, optional first-name label.
struct LiveParticipantMarker: View {
    let user: User?
    var name: String
    var isMe = false
    var isStale = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let user { AlongProfileAvatar(user: user, size: 40) }
                else { Circle().fill(AlongColor.surface).frame(width: 40, height: 40) }
            }
            .overlay(Circle().stroke(isMe ? AlongColor.navy : AlongColor.white, lineWidth: 3))
            .overlay(Circle().stroke(isMe ? AlongColor.white : AlongColor.navy, lineWidth: 1).padding(-1.5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .opacity(isStale ? 0.55 : 1)
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(AlongColor.white.opacity(0.95), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isMe ? "You" : "\(name)\(isStale ? ", location temporarily unavailable" : "")")
    }
}

/// The immersive walking map: route, two live markers, a navigation-style header and a compact bottom card.
struct LiveWalkMapView: View {
    @Bindable var vm: LiveWalkViewModel
    let onClose: () -> Void
    @State private var confirmEnd = false
    @Environment(\.openURL) private var openURL

    private var needsMyConfirmation: Bool {
        vm.status == .awaitingCompletion && !(vm.myParticipant?.hasConfirmedFinish ?? false)
    }
    private var waitingForPartner: Bool {
        vm.status == .awaitingCompletion && (vm.myParticipant?.hasConfirmedFinish ?? false)
    }

    var body: some View {
        ZStack {
            mapLayer
            VStack(spacing: AlongSpacing.xs) {
                if !vm.isMinimized { navigationHeader }
                banners
                Spacer()
                cameraButtons
                bottomCard
            }
            .padding(.horizontal, AlongSpacing.md)
            .padding(.bottom, AlongSpacing.xs)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Finished walking?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Yes, finish my walk") { Task { await vm.finish() } }
            Button("Keep walking", role: .cancel) {}
        } message: { Text("This stops sharing your location. \(vm.partner?.firstName ?? "Your buddy") will be asked to confirm.") }
    }

    // MARK: Map

    private var mapLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !vm.markersAnimating)) { context in
            Map(position: $vm.camera) {
                if let route = vm.route {
                    MapPolyline(coordinates: route.coordinates.map(\.cl))
                        .stroke(AlongColor.navy.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
                if let a = vm.activity {
                    Annotation("", coordinate: a.walk.to.coordinate.cl, anchor: .center) { AlongRouteEndDot() }
                }
                if let c = vm.myTrack.coordinate(at: context.date) {
                    Annotation("", coordinate: c, anchor: .bottom) {
                        LiveParticipantMarker(user: vm.me, name: vm.me.firstName, isMe: true)
                    }
                }
                if let c = vm.partnerTrack.coordinate(at: context.date), let p = vm.partner {
                    Annotation("", coordinate: c, anchor: .bottom) {
                        LiveParticipantMarker(user: p, name: p.firstName, isStale: vm.partnerIsStale(now: context.date))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in vm.userPannedMap() })
        .ignoresSafeArea()
    }

    // MARK: Header

    private var navigationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Walking to \(vm.destinationName)").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
            HStack(spacing: 6) {
                if let left = vm.remainingMeters {
                    Text("\(DistanceFormat.miles(left)) remaining").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.navy)
                    Text("·").foregroundStyle(AlongColor.textSecondary)
                    Text("\(max(Int((left / 1.35 / 60).rounded()), 1)) min").font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                }
                if let eta = vm.etaDate {
                    Text("·").foregroundStyle(AlongColor.textSecondary)
                    Text("Arrive \(eta.formatted(date: .omitted, time: .shortened))").font(AlongFont.body).foregroundStyle(AlongColor.textTertiary)
                }
            }
            ProgressView(value: vm.progress).tint(AlongColor.navy)
            if let step = vm.nextInstruction {
                Label(step, systemImage: "arrow.turn.up.right").font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary)
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .alongFloatingShadow()
        .padding(.top, AlongSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Banners (honest status, never hidden)

    @ViewBuilder private var banners: some View {
        if vm.locationDenied {
            banner("Location is off, so your position isn't on the map.", "location.slash", action: ("Settings", {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }))
        }
        if vm.connectionLost && vm.iAmSharing {
            banner("Reconnecting to your walk...", "wifi.exclamationmark")
        }
        if vm.isLowPower {
            banner("Low battery: Along is sending your location less often.", "battery.25percent")
        }
        if let message = vm.errorMessage { banner(message, "exclamationmark.circle") }
    }

    private func banner(_ text: String, _ symbol: String, action: (String, () -> Void)? = nil) -> some View {
        HStack(spacing: AlongSpacing.xs) {
            Image(systemName: symbol).foregroundStyle(AlongColor.navy)
            Text(text).font(AlongFont.caption).foregroundStyle(AlongColor.textPrimary)
            Spacer(minLength: 0)
            if let action { Button(action.0, action: action.1).font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy) }
        }
        .padding(.horizontal, AlongSpacing.sm + 2).padding(.vertical, AlongSpacing.xs + 2)
        .background(AlongColor.white, in: Capsule())
        .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
        .alongFloatingShadow()
    }

    // MARK: Camera buttons

    private var cameraButtons: some View {
        HStack(spacing: AlongSpacing.xs) {
            Spacer()
            VStack(spacing: AlongSpacing.xs) {
                cameraButton("location.fill", "Follow my location", vm.follow == .me) { vm.setFollow(.me) }
                cameraButton("person.2.fill", "Show both walkers", vm.follow == .both) { vm.setFollow(.both) }
                cameraButton("point.topleft.down.to.point.bottomright.curvepath", "Overview of the route", vm.follow == .route) { vm.setFollow(.route) }
                if vm.follow == .free {
                    cameraButton("scope", "Recenter", false) { vm.setFollow(.me) }
                }
            }
        }
    }

    private func cameraButton(_ symbol: String, _ label: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? AlongColor.white : AlongColor.navy)
                .frame(width: 44, height: 44)
                .background(selected ? AlongColor.navy : AlongColor.white, in: Circle())
                .overlay(Circle().stroke(AlongColor.border, lineWidth: selected ? 0 : 1))
                .alongFloatingShadow()
        }
        .buttonStyle(AlongPressStyle(scale: 0.94))
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack(spacing: AlongSpacing.sm) {
                HStack(spacing: -10) {
                    AlongProfileAvatar(user: vm.me, size: 38)
                    if let p = vm.partner { AlongProfileAvatar(user: p, size: 38) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Walking with \(vm.partner?.firstName ?? "your buddy")").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                    Text(statusLine).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
                Spacer(minLength: 0)
                Button { alongWithAnimation { vm.isMinimized.toggle() } } label: {
                    Text(vm.isMinimized ? "Show View" : "Pause View").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                        .frame(minHeight: AlongSize.minTouch)
                }
                .accessibilityHint("Hides or shows the navigation header. Location sharing is not affected.")
            }

            if needsMyConfirmation {
                confirmationPrompt
            } else if waitingForPartner {
                HStack(spacing: AlongSpacing.sm) {
                    ProgressView()
                    Text("Waiting for \(vm.partner?.firstName ?? "your buddy") to confirm...").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                }
                AlongButton(title: "Close", style: .secondary, action: onClose)
            } else {
                stats
                partnerStatus
                HStack(spacing: AlongSpacing.sm) {
                    AlongButton(title: "End Walk", isLoading: vm.isBusy) { confirmEnd = true }
                }
                Button { Task { await vm.setSharing(!vm.iAmSharing) } } label: {
                    Label(vm.iAmSharing ? "Stop Sharing Location" : "Resume Sharing Location",
                          systemImage: vm.iAmSharing ? "location.slash" : "location")
                        .font(AlongFont.subheadEmphasis).foregroundStyle(vm.iAmSharing ? AlongColor.destructive : AlongColor.navy)
                        .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityHint(vm.iAmSharing ? "Stops sending your location right away. Your buddy doesn't need to approve." : "Starts sending your location again.")
            }
        }
        .padding(AlongSpacing.md)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .alongFloatingShadow()
    }

    private var statusLine: String {
        if vm.status == .awaitingCompletion { return "Finishing up" }
        return vm.iAmSharing ? "Walk in progress · sharing your location" : "Walk in progress · not sharing your location"
    }

    private var stats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = vm.session?.startedAt.map { max(Int(context.date.timeIntervalSince($0)), 0) } ?? 0
            HStack(spacing: 0) {
                statCell(elapsedText(elapsed), "elapsed")
                statCell(DistanceFormat.miles(vm.tracker.distanceMeters), "walked")
                statCell(vm.destinationName, "destination")
            }
        }
    }

    private func elapsedText(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Location temporarily unavailable" with the last update time, shown instead of a fake position.
    @ViewBuilder private var partnerStatus: some View {
        if vm.partnerParticipant?.isSharing == false {
            Label("\(vm.partner?.firstName ?? "Your buddy") stopped sharing their location.", systemImage: "location.slash")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        } else {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                if vm.partnerIsStale(now: context.date) {
                    Label(staleText(now: context.date), systemImage: "location.slash")
                        .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
            }
        }
    }

    private func staleText(now: Date) -> String {
        guard let seen = vm.partnerSeenAt else { return "Location temporarily unavailable" }
        let s = Int(now.timeIntervalSince(seen))
        return "Location temporarily unavailable · updated \(s < 60 ? "\(s)s" : "\(s / 60) min") ago"
    }

    private var confirmationPrompt: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            Text("\(vm.partner?.firstName ?? "Your buddy") finished walking. Did you finish together?")
                .font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
            AlongButton(title: "Yes, we finished", isLoading: vm.isBusy) { Task { await vm.finish() } }
            AlongButton(title: "We didn't finish together", style: .secondary) { Task { await vm.endEarly() } }
        }
    }
}
