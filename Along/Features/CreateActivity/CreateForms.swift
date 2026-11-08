import SwiftUI
import MapKit

// MARK: - Walk

struct CreateWalkView: View {
    @Bindable var vm: CreateActivityViewModel
    let onPublished: () -> Void
    @State private var picking: Slot?

    enum Slot: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        FormScaffold(title: "", cta: "Publish Walk", isEnabled: vm.walkIsValid, isLoading: vm.isPublishing) {
            Task { if await vm.publishWalk() { onPublished() } }
        } content: {
            Text("Where are we walking?")
                .font(AlongFont.walkScreenHeading).foregroundStyle(AlongColor.textPrimary)
            AlongFieldRow(label: "Starting location", value: vm.from?.publicLabel, placeholder: "Starting street or place", symbol: "location") { picking = .from }
            AlongFieldRow(label: "Destination", value: vm.to?.publicLabel, placeholder: "Where are you headed?", symbol: "flag") { picking = .to }
            if let hint = vm.walkHint { Text(hint).font(AlongFont.caption).foregroundStyle(AlongColor.destructive) }
            routePreview
            WhenField(label: "Date & time", date: $vm.start)
            OptionField(label: "Walking pace", options: Pace.allCases.map(\.rawValue), selection: Binding(
                get: { Pace.allCases.firstIndex(of: vm.pace) ?? 0 }, set: { vm.pace = Pace.allCases[$0] }))
            SpotsField(label: "Available spots", spots: $vm.spots)
            AlongTextField(label: "Description", text: $vm.note, prompt: "Optional", axis: .vertical, lines: 1...3, limit: 140)
            AlongTextField(label: "What's on your mind?", text: $vm.mindPrompt, prompt: "Life, work, random thoughts... anything really.",
                           axis: .vertical, lines: 1...3, limit: 140)
            AlongTextField(label: "Meeting spot", text: $vm.meetingDetails, prompt: "Shared only after you accept someone", axis: .vertical, lines: 1...3, limit: 140)
            HostVisibilityField(vm: vm)
        }
        .sheet(item: $picking) { slot in
            PlaceSearchView(title: slot == .from ? "Starting point" : "Destination") { place in
                if slot == .from { vm.from = place } else { vm.to = place }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(AlongRadius.sheet)
            .presentationBackground(AlongColor.offWhite)
        }
        .task(id: [vm.from?.coordinate, vm.to?.coordinate].compactMap { $0 }) { await vm.updateRoute() }
    }

    @ViewBuilder private var routePreview: some View {
        if let from = vm.from, let to = vm.to, vm.routeIsValid {
            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                Map(position: $vm.routeCamera, interactionModes: []) {
                    MapPolyline(coordinates: (vm.route?.coordinates ?? [from.coordinate, to.coordinate]).map(\.cl))
                        .stroke(AlongColor.navy, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    Annotation("Start", coordinate: from.coordinate.cl, anchor: .center) {
                        Circle().fill(AlongColor.navy).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                    Annotation("End", coordinate: to.coordinate.cl, anchor: .center) { AlongRouteEndDot() }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                Text(vm.route.map { "\($0.summary) · approximate route" } ?? "Finding route…")
                    .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Shared form pieces

struct FormScaffold<Content: View>: View {
    let title: String
    let cta: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlongSpacing.lg) {
                content()
            }
            .padding(.horizontal, AlongSpacing.gutter)
            .padding(.top, AlongSpacing.sm)
            .padding(.bottom, AlongSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .alongScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AlongButton(title: cta, isLoading: isLoading, action: action)
                .disabled(!isEnabled)
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.vertical, AlongSpacing.sm)
                .background(AlongColor.offWhite.overlay(alignment: .top) { AlongDivider() }.ignoresSafeArea(edges: .bottom))
        }
    }
}

struct WhenField: View {
    let label: String
    @Binding var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Text(label).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            DatePicker(label, selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().datePickerStyle(.compact).tint(AlongColor.navy)
                .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch, alignment: .leading)
        }
    }
}

struct OptionField: View {
    let label: String
    let options: [String]
    @Binding var selection: Int
    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            Text(label).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            AlongSegmentedControl(options: options, selection: $selection)
        }
    }
}

struct SpotsField: View {
    var label = "Spots"
    @Binding var spots: Int
    var body: some View {
        OptionField(label: label, options: ["1", "2", "3", "4", "5"], selection: Binding(get: { spots - 1 }, set: { spots = $0 + 1 }))
    }
}

/// Public: your profile shows. Private: the walk is still on the map for everyone, but you appear as "Anonymous Walker".
struct HostVisibilityField: View {
    @Bindable var vm: CreateActivityViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            OptionField(label: "Visibility", options: Visibility.allCases.map(\.rawValue), selection: Binding(
                get: { Visibility.allCases.firstIndex(of: vm.visibility) ?? 0 }, set: { vm.visibility = Visibility.allCases[$0] }))
            Text(vm.hidesIdentity ? "Your walk will appear on the map, but your identity will remain hidden."
                                  : "Your profile will be visible to people exploring this walk.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            Text("Private walks are still visible to everyone. Only your identity is hidden.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)

            if vm.hidesIdentity {
                VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                    Text("Interests to show instead of a profile").font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
                    if vm.myHobbies.isEmpty {
                        Text("Add interests to your profile and you can show a few of them here. People will only see the ones you pick.")
                            .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(vm.myHobbies, id: \.self) { hobby in
                                Button { Haptics.selection(); vm.toggleInterest(hobby) } label: {
                                    AlongChip(title: hobby, isSelected: vm.hostInterests.contains(hobby)).frame(minHeight: AlongSize.minTouch)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(vm.hostInterests.contains(hobby) ? .isSelected : [])
                            }
                        }
                        Text("Up to four. Your name, photo, socials and bio stay hidden.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                }
                .padding(.top, AlongSpacing.xs)
                .transition(.opacity)
            }
        }
        .alongAnimation(value: vm.hidesIdentity)
    }
}
