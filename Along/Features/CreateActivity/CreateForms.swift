import SwiftUI
import MapKit

// MARK: - Walk

struct CreateWalkView: View {
    @Bindable var vm: CreateActivityViewModel
    let onPublished: () -> Void
    @State private var picking: Slot?

    enum Slot: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        FormScaffold(title: "Create a walk", cta: "Publish Walk", isEnabled: vm.walkIsValid, isLoading: vm.isPublishing) {
            Task { if await vm.publishWalk() { onPublished() } }
        } content: {
            AlongFieldRow(label: "From", value: vm.from?.publicLabel, placeholder: "Starting street or place", symbol: "location") { picking = .from }
            AlongFieldRow(label: "To", value: vm.to?.publicLabel, placeholder: "Where are you headed?", symbol: "flag") { picking = .to }
            if let hint = vm.walkHint { Text(hint).font(AlongFont.caption).foregroundStyle(AlongColor.destructive) }
            routePreview
            WhenField(label: "When", date: $vm.start)
            OptionField(label: "Pace", options: Pace.allCases.map(\.rawValue), selection: Binding(
                get: { Pace.allCases.firstIndex(of: vm.pace) ?? 0 }, set: { vm.pace = Pace.allCases[$0] }))
            SpotsField(spots: $vm.spots)
            AlongTextField(label: "A little note", text: $vm.note, prompt: "Optional", axis: .vertical, lines: 1...3, limit: 140)
            AlongTextField(label: "Meeting spot", text: $vm.meetingDetails, prompt: "Shared only after you accept someone", axis: .vertical, lines: 1...3, limit: 140)
            VisibilityField(visibility: $vm.visibility)
        }
        .sheet(item: $picking) { slot in
            PlaceSearchView(mode: .places, title: slot == .from ? "Starting point" : "Destination") { place in
                if slot == .from { vm.from = place } else { vm.to = place }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(AlongRadius.sheet)
            .presentationBackground(AlongColor.offWhite)
        }
        .task(id: [vm.from?.coordinate, vm.to?.coordinate].compactMap { $0 }) { await vm.updateRoute() }
    }

    @ViewBuilder private var routePreview: some View {
        if let from = vm.from, let to = vm.to, vm.walkIsValid {
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

// MARK: - Cowork

struct CreateCoworkView: View {
    @Bindable var vm: CreateActivityViewModel
    let onPublished: () -> Void
    @State private var picking = false

    var body: some View {
        FormScaffold(title: "Create a session", cta: "Publish Session", isEnabled: vm.coworkIsValid, isLoading: vm.isPublishing) {
            Task { if await vm.publishCowork() { onPublished() } }
        } content: {
            AlongFieldRow(label: "Where", value: vm.venue?.name, placeholder: "Search for a café", symbol: "cup.and.saucer") { picking = true }
            if let venue = vm.venue {
                Label("Public listing will say “\(venue.area) · Coffee shop”.", systemImage: "eye.slash")
                    .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
            }
            WhenField(label: "When", date: $vm.start)
            VStack(alignment: .leading, spacing: AlongSpacing.xs) {
                Text("Until").font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
                DatePicker("Until", selection: Binding(get: { vm.end }, set: { vm.end = $0 }),
                           in: vm.start.addingTimeInterval(15 * 60)..., displayedComponents: .hourAndMinute)
                    .labelsHidden().datePickerStyle(.compact).tint(AlongColor.navy)
                    .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch, alignment: .leading)
            }
            OptionField(label: "Work style", options: WorkStyle.allCases.map(\.rawValue), selection: Binding(
                get: { WorkStyle.allCases.firstIndex(of: vm.style) ?? 0 }, set: { vm.style = WorkStyle.allCases[$0] }))
            SpotsField(spots: $vm.spots)
            AlongTextField(label: "Working on", text: $vm.note, prompt: "Optional", axis: .vertical, lines: 1...3, limit: 140)
            AlongTextField(label: "Meeting spot", text: $vm.meetingDetails, prompt: "Where to find you — shared only after you accept", axis: .vertical, lines: 1...3, limit: 140)
            VisibilityField(visibility: $vm.visibility)
        }
        .sheet(isPresented: $picking) {
            PlaceSearchView(mode: .cafes, title: "Find a café") { vm.venue = $0 }
                .presentationDetents([.large])
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
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
    @Binding var spots: Int
    var body: some View {
        OptionField(label: "Spots", options: ["1", "2", "3", "4", "5"], selection: Binding(get: { spots - 1 }, set: { spots = $0 + 1 }))
    }
}

struct VisibilityField: View {
    @Binding var visibility: Visibility
    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.xs) {
            OptionField(label: "Visibility", options: Visibility.allCases.map(\.rawValue), selection: Binding(
                get: { Visibility.allCases.firstIndex(of: visibility) ?? 0 }, set: { visibility = Visibility.allCases[$0] }))
            Text(visibility == .public ? "Shown on the map to people in Manhattan, with approximate locations." : "Private plans stay off the map. Only you can see them.")
                .font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
        }
    }
}
