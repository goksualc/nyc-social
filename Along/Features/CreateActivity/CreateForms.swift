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

            // 1 · Route
            VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                AlongFieldRow(label: "Starting location", value: vm.from?.publicLabel, placeholder: "Starting street or place", symbol: "location") { picking = .from }
                AlongFieldRow(label: "Destination", value: vm.to?.publicLabel, placeholder: "Where are you headed?", symbol: "flag") { picking = .to }
                if let hint = vm.walkHint { Text(hint).font(AlongFont.caption).foregroundStyle(AlongColor.destructive) }
                routePreview
            }

            // 2 · When and how
            section("When") {
                WhenField(label: "Date & time", date: $vm.start)
                OptionField(label: "Walking pace", options: Pace.allCases.map(\.rawValue), selection: Binding(
                    get: { Pace.allCases.firstIndex(of: vm.pace) ?? 0 }, set: { vm.pace = Pace.allCases[$0] }))
                SpotsField(label: "Available spots", spots: $vm.spots)
            }

            // 3 · What it's about
            section("What it's about") {
                AlongTextField(label: "What's on your mind?", text: $vm.mindPrompt,
                               prompt: "Career thoughts, life updates, random overthinking... anything really.",
                               axis: .vertical, lines: 1...3, limit: 140)
                TagPicker(vm: vm)
                AlongTextField(label: "Description", text: $vm.note, prompt: "Optional", axis: .vertical, lines: 1...3, limit: 140)
                AlongTextField(label: "Meeting spot", text: $vm.meetingDetails, prompt: "Shared only after you accept someone", axis: .vertical, lines: 1...3, limit: 140)
            }

            // 4 · Who sees you
            section("Who sees you") { HostVisibilityField(vm: vm) }

            WalkSummaryCard(vm: vm)
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

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AlongSpacing.md) {
            Text(title).font(AlongFont.sectionHeading).foregroundStyle(AlongColor.textPrimary)
            content()
        }
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
                Text(vm.routeLine ?? "Finding route…")
                    .font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(vm.routeLine ?? "Finding route")
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

/// Public / Private Host / Anonymous Host as three tappable rows, each with one line saying exactly what it shows.
struct HostVisibilityField: View {
    @Bindable var vm: CreateActivityViewModel

    var body: some View {
        VStack(spacing: AlongSpacing.xs) {
            ForEach(CreateActivityViewModel.HostMode.allCases) { mode in
                let on = vm.hostMode == mode
                Button { Haptics.selection(); alongWithAnimation(.alongQuick) { vm.hostMode = mode } } label: {
                    HStack(alignment: .top, spacing: AlongSpacing.sm) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(on ? AlongColor.navy : AlongColor.border)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                            Text(mode.detail).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(AlongSpacing.md - 2)
                    .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch, alignment: .leading)
                    .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous)
                        .stroke(on ? AlongColor.navy : AlongColor.border, lineWidth: on ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text("Every walk is on the map for everyone. This only decides what people see about you.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
        }
    }
}

/// Up to three optional topic tags.
struct TagPicker: View {
    @Bindable var vm: CreateActivityViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            HStack {
                Text("Topics").font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
                Spacer()
                Text("\(vm.tags.count) of \(CreateActivityViewModel.maxTags)").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
            FlowLayout(spacing: 8) {
                ForEach(CreateActivityViewModel.tagOptions, id: \.self) { tag in
                    let on = vm.tags.contains(tag)
                    let full = !on && vm.tags.count >= CreateActivityViewModel.maxTags
                    Button { vm.toggleTag(tag) } label: {
                        AlongChip(title: tag, isSelected: on).frame(minHeight: AlongSize.minTouch).opacity(full ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(full)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if vm.hostMode == .anonymousHost && !vm.tags.isEmpty {
                Text("Anonymous Host shares no tags. They stay off this walk.").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
        }
    }
}

/// What the walk will look like, updating as the form changes.
struct WalkSummaryCard: View {
    let vm: CreateActivityViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.sm) {
            Text("Your walk").font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
            row("point.topleft.down.to.point.bottomright.curvepath", vm.routeLine ?? "Choose a start and a destination")
            row("calendar", vm.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
            row("speedometer", "\(vm.pace.rawValue) pace · \(vm.spots) \(vm.spots == 1 ? "spot" : "spots")")
            row(vm.hostMode.hidesIdentity ? "eye.slash" : "person.crop.circle", vm.hostMode.rawValue)
            if !vm.publishedTags.isEmpty {
                FlowLayout(spacing: 6) { ForEach(vm.publishedTags, id: \.self) { AlongChip(title: $0) } }
            }
        }
        .padding(AlongSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AlongRadius.card, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AlongSpacing.sm) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(AlongColor.navy).frame(width: 20)
            Text(text).font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
