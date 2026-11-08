import SwiftUI

/// Shown once BOTH people confirmed. Calm and minimal: no confetti, no points, no claims about wellbeing.
struct WalkCompletionView: View {
    @Bindable var vm: LiveWalkViewModel
    let onClose: () -> Void
    @State private var appeared = false

    private var walk: CompletedWalk? { vm.finishedWalk }
    private var duration: Int { walk?.durationSeconds ?? vm.session?.durationSeconds ?? 0 }
    private var distance: Int { walk?.distanceMeters ?? vm.session?.distanceMeters ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: AlongSpacing.lg) {
                HStack(spacing: -14) {
                    AlongProfileAvatar(user: vm.me, size: 84)
                    if let p = vm.partner { AlongProfileAvatar(user: p, size: 84) }
                }
                .scaleEffect(appeared ? 1 : 0.85).opacity(appeared ? 1 : 0)
                .padding(.top, AlongSpacing.xl)

                VStack(spacing: 6) {
                    Text("Another walk, another good conversation.")
                        .font(.system(.title, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                        .foregroundStyle(AlongColor.textPrimary)
                    Text("You walked Along!").font(AlongFont.body).foregroundStyle(AlongColor.textTertiary)
                }
                .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)

                VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                    Text("You walked with \(vm.partner?.firstName ?? "your buddy").")
                        .font(AlongFont.headline).foregroundStyle(AlongColor.textPrimary)
                    if let route = walk?.route ?? vm.activity?.publicLocationLabel {
                        Text(route).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary)
                    }
                    Divider()
                    row("clock", DistanceFormat.duration(duration))
                    row("figure.walk", DistanceFormat.miles(Double(distance)))
                    row("calendar", (walk?.startedAt ?? vm.session?.startedAt ?? .now).formatted(date: .long, time: .omitted))
                }
                .padding(AlongSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .alongCard()
                .opacity(appeared ? 1 : 0)

                memoryChoices
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.bottom, AlongSpacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: AlongSpacing.xs) {
                AlongButton(title: "Back to Explore", action: onClose)
                NavigationLink { WalkHistoryView(store: vm.store) } label: {
                    Text("View Walk History").font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.navy)
                        .frame(maxWidth: .infinity, minHeight: AlongSize.button)
                }
            }
            .padding(.horizontal, AlongSpacing.gutter).padding(.vertical, AlongSpacing.sm)
            .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadFinishedWalk() }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
        .onAppear { Haptics.success() }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(AlongFont.body).foregroundStyle(AlongColor.textPrimary) }
            icon: { Image(systemName: symbol).foregroundStyle(AlongColor.navy).frame(width: 22) }
    }

    /// Each person decides for themselves; the walk is private by default.
    private var memoryChoices: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            AlongSectionLabel("This memory")
            Toggle("Count it in my public walk total", isOn: Binding(
                get: { walk?.showOnProfile ?? false }, set: { on in Task { await vm.setMemoryPrefs(showOnProfile: on) } }))
            Toggle("Remember who I walked with", isOn: Binding(
                get: { walk?.revealPartner ?? false }, set: { on in Task { await vm.setMemoryPrefs(revealPartner: on) } }))
            Text("Private by default. Names only appear in history when you both choose it.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
        .tint(AlongColor.navy)
        .font(AlongFont.body)
        .disabled(walk == nil)
    }
}
