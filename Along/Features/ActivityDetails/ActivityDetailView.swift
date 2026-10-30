import SwiftUI
import MapKit

/// Resolves the store from the environment, then hands off to the view that owns the view model.
struct ActivityDetailView: View {
    let activityID: ID
    var isSheet = false
    @Environment(AppStore.self) private var store

    var body: some View {
        ActivityDetailContent(store: store, activityID: activityID, isSheet: isSheet)
    }
}

private struct ActivityDetailContent: View {
    @State private var vm: ActivityDetailViewModel
    let isSheet: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, activityID: ID, isSheet: Bool) {
        _vm = State(initialValue: ActivityDetailViewModel(store: store, activityID: activityID))
        self.isSheet = isSheet
    }

    var body: some View {
        Group {
            if let activity = vm.activity {
                content(activity)
            } else {
                AlongEmptyState(title: "This plan is gone.", message: "It may have ended or been removed.")
                    .frame(maxHeight: .infinity)
            }
        }
        .alongScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                        .accessibilityLabel("Close")
                }
            }
            if vm.activity != nil, !vm.isHost {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report plan", systemImage: "flag") { vm.showReport = true }
                        Button("Block \(vm.host?.firstName ?? "host")", systemImage: "nosign", role: .destructive) { vm.confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .sheet(isPresented: $vm.showEdit) {
            if let a = vm.activity {
                EditActivitySheet(activity: a)
                    .presentationDetents([.large])
                    .presentationCornerRadius(AlongRadius.sheet)
                    .presentationBackground(AlongColor.offWhite)
            }
        }
        .sheet(item: $vm.profile) { item in
            UserProfileSheet(userID: item.id)
                .presentationDetents([.large])
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
        .reportDialog(isPresented: $vm.showReport) { reason in Task { await vm.report(reason) } }
        .blockDialog(name: vm.host?.firstName ?? "this person", isPresented: $vm.confirmBlock) {
            Task { await vm.blockHost(); dismiss() }
        }
        .confirmationDialog("Cancel this plan?", isPresented: $vm.confirmCancel, titleVisibility: .visible) {
            Button("Cancel plan", role: .destructive) { Task { await vm.cancel() } }
            Button("Keep plan", role: .cancel) {}
        } message: { Text("Guests will be told it's off and chats will close.") }
        .confirmationDialog("Leave this plan?", isPresented: $vm.confirmLeave, titleVisibility: .visible) {
            Button("Leave plan", role: .destructive) { Task { await vm.leave() } }
            Button("Stay", role: .cancel) {}
        } message: { Text("You'll lose access to the meeting details and chat.") }
        .task { await vm.loadRoute() }
    }

    // MARK: Content

    private func content(_ a: Activity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                header(a)
                infoCard(a)
                if !a.note.isEmpty { noteView(a) }
                locationPreview(a)
                if a.hasPreciseAccess && !a.meetingDetails.isEmpty { meetingCard(a) }
                if vm.isHost { managementSection(a) } else { hostCard }
                if !vm.isHost { safetyRow }
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.top, AlongSpacing.xs)
            .padding(.bottom, AlongSpacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(a) }
    }

    private func header(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: a.kind.symbol).font(.system(size: 11, weight: .semibold))
                Text(a.kind.label).font(AlongFont.label)
                if a.visibility == .private { Text("· Private").font(AlongFont.label) }
            }
            .foregroundStyle(AlongColor.navy)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(AlongColor.surface, in: Capsule())

            Text(a.title)
                .font(.system(.title, design: .serif, weight: .semibold))
                .foregroundStyle(AlongColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let host = vm.host {
                Button { vm.profile = IDItem(id: host.id) } label: {
                    HStack(spacing: AlongSpacing.xs) {
                        AlongProfileAvatar(user: host, size: 28)
                        Text(vm.isHost ? "Hosted by you" : "Hosted by \(host.firstName)")
                            .font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                    }
                    .frame(minHeight: AlongSize.minTouch - 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoCard(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            AlongInfoRow(symbol: "clock", text: ActivityTime.summary(a, now: vm.store.now))
            AlongInfoRow(symbol: a.kind == .walk ? "arrow.triangle.turn.up.right.diamond" : "mappin.and.ellipse",
                         text: a.publicLocationLabel,
                         secondary: a.hasPreciseAccess ? nil : "General area only")
            switch a.details {
            case .walk(let w): AlongInfoRow(symbol: "figure.walk", text: "\(w.pace.rawValue) pace")
            case .cowork(let c): AlongInfoRow(symbol: "laptopcomputer", text: "Work style: \(Self.styleName(c.style))")
            }
            AlongInfoRow(symbol: "person.2",
                         text: a.isFull ? "No spots left" : (a.spotsLeft == 1 ? "1 spot available" : "\(a.spotsLeft) spots available"))
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alongCard()
    }

    private static func styleName(_ s: WorkStyle) -> String {
        switch s { case .deepWork: "Focused"; case .social: "Social"; case .buildTogether: "Build together" }
    }

    private func noteView(_ a: Activity) -> some View {
        Text("“\(a.note)”")
            .font(.system(.title3, design: .serif))
            .foregroundStyle(AlongColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Location

    @ViewBuilder
    private func locationPreview(_ a: Activity) -> some View {
        switch a.details {
        case .walk(let w):
            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                Map(position: $vm.routeCamera, interactionModes: []) {
                    let coords = (vm.route?.coordinates ?? [w.from.coordinate, w.to.coordinate]).map(\.cl)
                    MapPolyline(coordinates: coords).stroke(AlongColor.navy, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    Annotation("Start", coordinate: w.from.coordinate.cl, anchor: .center) {
                        Circle().fill(AlongColor.navy).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                    Annotation("End", coordinate: w.to.coordinate.cl, anchor: .center) { AlongRouteEndDot() }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                .accessibilityLabel("Route preview from \(w.from.publicLabel) to \(w.to.publicLabel)")

                Text(routeCaption)
                    .font(AlongFont.caption)
                    .foregroundStyle(AlongColor.textTertiary)
            }
        case .cowork(let c):
            HStack(spacing: 0) {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: c.venue.coordinate.cl, distance: 1100)), interactionModes: []) {
                    MapCircle(center: c.venue.coordinate.cl, radius: 160)
                        .foregroundStyle(AlongColor.navy.opacity(0.10))
                        .stroke(AlongColor.navy.opacity(0.5), lineWidth: 1.5)
                    Annotation("", coordinate: c.venue.coordinate.cl, anchor: .center) { AlongMapMarker(kind: .cowork) }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(width: 112, height: 112)
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.hasPreciseAccess && !c.venue.name.isEmpty ? c.venue.name : "Coffee shop")
                        .font(AlongFont.headline).foregroundStyle(AlongColor.textPrimary)
                    Text(c.venue.area).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                    Text(a.hasPreciseAccess ? "Exact spot below" : "Exact café shared once accepted")
                        .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                }
                .padding(AlongSpacing.md)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(AlongColor.white)
            .clipShape(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    private var routeCaption: String {
        guard let r = vm.route else { return "Approximate route" }
        return "\(r.summary) · approximate route"
    }

    private func meetingCard(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Label("Meeting details", systemImage: "mappin.circle")
                .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
            if let c = a.cowork, let address = c.venue.address, !address.isEmpty {
                Text("\(c.venue.name), \(address)").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
            }
            Text(a.meetingDetails).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
            Text(vm.isHost ? "Only you and accepted guests can see this." : "Shared with you because you're in. Please keep it between us.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlongColor.surface, in: RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
    }

    // MARK: People

    @ViewBuilder
    private var hostCard: some View {
        if let host = vm.host {
            Button { vm.profile = IDItem(id: host.id) } label: {
                VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                    HStack(spacing: AlongSpacing.sm) {
                        AlongProfileAvatar(user: host, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.firstName).font(AlongFont.headline).foregroundStyle(AlongColor.textPrimary)
                            Text(host.neighborhood).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
                    }
                    Text(host.bio).font(AlongFont.subhead).foregroundStyle(AlongColor.textPrimary).multilineTextAlignment(.leading)
                    FlowLayout(spacing: 6) {
                        ForEach(host.interests) { AlongChip(title: $0.rawValue) }
                    }
                }
                .padding(AlongSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .alongCard()
            }
            .buttonStyle(AlongPressStyle(scale: 0.99))
            .accessibilityHint("Opens \(host.firstName)'s profile")
        }
    }

    private var safetyRow: some View {
        HStack(spacing: AlongSpacing.lg) {
            Button { vm.showReport = true } label: { Label("Report", systemImage: "flag") }
            Button { vm.confirmBlock = true } label: { Label("Block \(vm.host?.firstName ?? "")", systemImage: "nosign") }
        }
        .font(AlongFont.subheadEmphasis)
        .foregroundStyle(AlongColor.textTertiary)
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .frame(minHeight: AlongSize.minTouch)
        .frame(maxWidth: .infinity)
    }

    // MARK: Host management

    private func managementSection(_ a: Activity) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            AlongSectionLabel("Requests")
            if vm.pendingRequests.isEmpty {
                Text("No pending requests.").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            }
            ForEach(vm.pendingRequests) { request in
                if let user = vm.store.user(request.requesterID) {
                    VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                        Button { vm.profile = IDItem(id: user.id) } label: {
                            HStack(spacing: AlongSpacing.sm) {
                                AlongProfileAvatar(user: user, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(user.firstName) wants to join").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                                    Text(user.bio).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: AlongSpacing.xs) {
                            if a.isFull {
                                Text("Plan is full").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                            } else {
                                AlongSmallButton(title: "Accept", filled: true) { Task { await vm.respond(request, accept: true) } }
                            }
                            AlongSmallButton(title: "Decline") { Task { await vm.respond(request, accept: false) } }
                        }
                    }
                    .padding(AlongSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alongCard()
                    .transition(.opacity)
                }
            }

            AlongSectionLabel("Going (\(vm.participants.count) of \(a.capacity))")
            if vm.participants.isEmpty {
                Text("No one yet.").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
            }
            ForEach(vm.participants) { person in
                HStack(spacing: AlongSpacing.sm) {
                    Button { vm.profile = IDItem(id: person.id) } label: {
                        HStack(spacing: AlongSpacing.sm) {
                            AlongProfileAvatar(user: person, size: 36)
                            Text(person.firstName).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                        }
                        .frame(minHeight: AlongSize.minTouch)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let c = vm.conversation(with: person) {
                        NavigationLink(value: AlongRoute.conversation(c.id)) {
                            Label("Message", systemImage: "bubble.left")
                                .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.navy)
                                .frame(minHeight: AlongSize.minTouch)
                        }
                    }
                }
            }
        }
        .alongAnimation(value: vm.pendingRequests.count)
    }

    // MARK: Action bar

    @ViewBuilder
    private func actionBar(_ a: Activity) -> some View {
        let bar = VStack(spacing: AlongSpacing.xxs) {
            if vm.isHost {
                if vm.isLive {
                    AlongButton(title: "Edit plan", style: .secondary) { vm.showEdit = true }
                    AlongButton(title: "Cancel plan", style: .ghost) { vm.confirmCancel = true }
                } else { endedLabel(a) }
            } else if !vm.isLive {
                endedLabel(a)
            } else {
                switch vm.role {
                case .none:
                    AlongButton(title: a.isFull ? "Plan is full" : "Request to Join", isLoading: vm.isWorking) {
                        Task { await vm.requestToJoin() }
                    }
                    .disabled(a.isFull)
                case .pending:
                    AlongButton(title: "Request Sent", symbol: "checkmark", style: .secondary) {}.allowsHitTesting(false)
                    AlongButton(title: "Cancel request", style: .ghost) { Task { await vm.withdraw() } }
                case .accepted:
                    if let c = vm.hostConversation {
                        NavigationLink(value: AlongRoute.conversation(c.id)) {
                            Text("Message \(vm.host?.firstName ?? "host")")
                                .font(AlongFont.bodyEmphasis).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: AlongSize.button)
                                .background(AlongColor.navy, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                        }
                        .buttonStyle(AlongPressStyle())
                    } else {
                        AlongButton(title: "You're in", symbol: "checkmark", style: .secondary) {}.allowsHitTesting(false)
                    }
                    AlongButton(title: "Leave plan", style: .ghost) { vm.confirmLeave = true }
                case .declined:
                    AlongButton(title: "Request declined", style: .secondary) {}.disabled(true)
                case .host:
                    EmptyView()
                }
            }
        }
        .alongAnimation(value: vm.role)
        .padding(.horizontal, AlongSpacing.gutter)
        .padding(.top, AlongSpacing.sm)
        .padding(.bottom, AlongSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
        bar
    }

    private func endedLabel(_ a: Activity) -> some View {
        Text(a.isCancelled ? "This plan was cancelled" : "This plan has ended")
            .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textTertiary)
            .frame(maxWidth: .infinity, minHeight: AlongSize.button)
    }
}

// MARK: - Shared safety dialogs

extension View {
    func reportDialog(isPresented: Binding<Bool>, onSelect: @escaping (ReportReason) -> Void) -> some View {
        confirmationDialog("Report", isPresented: isPresented, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in Button(reason.rawValue) { onSelect(reason) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Tell us what's wrong. Reports are reviewed by our team.") }
    }

    func blockDialog(name: String, isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        confirmationDialog("Block \(name)?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Block", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: { Text("You won't see each other's plans, requests or messages.") }
    }
}
