import SwiftUI
import MapKit

struct ExploreView: View {
    @State private var vm: ExploreViewModel
    @Environment(AppStore.self) private var store
    private let location: LocationService

    init(store: AppStore, location: LocationService) {
        _vm = State(initialValue: ExploreViewModel(store: store, location: location))
        self.location = location
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            VStack(spacing: AlongSpacing.xs) {
                header
                filterBar
                Spacer(minLength: 0)
            }
            bottomLayer
        }
        .background(AlongColor.offWhite)
        .sheet(item: $vm.presented) { item in
            NavigationStack {
                ActivityDetailView(activityID: item.id, isSheet: true)
                    .alongDestinations()
            }
            .alongToasts()
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(AlongRadius.sheet)
            .presentationBackground(AlongColor.offWhite)
        }
        .sheet(isPresented: $vm.isCreating) {
            CreateActivityFlow(initialKind: vm.createKind)
                .alongToasts()
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $vm.camera, bounds: ExploreViewModel.bounds) {
            if location.isAuthorized && store.settings.useLocationToCenterMap { UserAnnotation() }

            ForEach(vm.walks) { walk in
                if let (a, b) = walk.routeEndpoints {
                    MapPolyline(coordinates: [a, b])
                        .stroke(AlongColor.navy.opacity(vm.selectedID == walk.id ? 0.7 : 0.35),
                                style: StrokeStyle(lineWidth: vm.selectedID == walk.id ? 4 : 3, lineCap: .round, dash: [1, 7]))
                    Annotation("", coordinate: b, anchor: .center) { AlongRouteEndDot() }
                }
            }

            ForEach(vm.activities) { activity in
                Annotation(activity.title, coordinate: activity.mapCoordinate, anchor: .center) {
                    AlongMapMarker(kind: activity.kind, isSelected: vm.selectedID == activity.id)
                        .onTapGesture { vm.select(activity) }
                        .accessibilityLabel("\(activity.kind.label): \(activity.title), \(ActivityTime.summary(activity, now: store.now))")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .onTapGesture { vm.deselect() }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: AlongSpacing.xs) {
                AlongMark(size: 22)
                Text("Manhattan, NYC")
                    .font(AlongFont.subheadEmphasis)
                    .foregroundStyle(AlongColor.textPrimary)
            }
            .padding(.leading, AlongSpacing.sm + 2)
            .padding(.trailing, AlongSpacing.md)
            .frame(minHeight: AlongSize.minTouch - 4)
            .background(AlongColor.white, in: Capsule())
            .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
            .alongFloatingShadow()
            .accessibilityElement(children: .combine)
            Spacer()
        }
        .padding(.horizontal, AlongSpacing.md)
        .padding(.top, AlongSpacing.xs)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AlongSpacing.xs) {
                ForEach(ExploreViewModel.Filter.allCases) { f in
                    AlongFilterPill(title: f.rawValue, isSelected: vm.filter == f) { vm.setFilter(f) }
                }
            }
            .padding(.horizontal, AlongSpacing.md)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: Bottom

    private var showsSheet: Bool { vm.selected == nil }

    private var bottomLayer: some View {
        ZStack(alignment: .bottom) {
            floatingButtons
            if let selected = vm.selected {
                ActivityPreviewCard(activity: selected, host: vm.host(of: selected), now: store.now,
                                    onOpen: { vm.open(selected) }, onClose: { vm.deselect() })
                    .padding(.horizontal, AlongSpacing.md)
                    .padding(.bottom, AlongSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                discoverySheet
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alongAnimation(value: vm.selectedID)
    }

    private var floatingButtons: some View {
        VStack(spacing: AlongSpacing.sm) {
            Spacer()
            Button { Task { await vm.locateMe() } } label: {
                Image(systemName: "location")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AlongColor.navy)
                    .frame(width: 48, height: 48)
                    .background(AlongColor.white, in: Circle())
                    .overlay(Circle().stroke(AlongColor.border, lineWidth: 1))
                    .alongFloatingShadow()
            }
            .buttonStyle(AlongPressStyle(scale: 0.94))
            .accessibilityLabel("Show my location")

            Button { Haptics.light(); vm.startCreating() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AlongColor.white)
                    .frame(width: 58, height: 58)
                    .background(AlongColor.navy, in: Circle())
                    .alongFloatingShadow()
            }
            .buttonStyle(AlongPressStyle(scale: 0.94))
            .accessibilityLabel("Create a plan")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, AlongSpacing.md)
        .padding(.bottom, (vm.selected == nil ? min(vm.sheetHeight, 240) : 190) + AlongSpacing.sm)
        .opacity(vm.detent == .collapsed || vm.selected != nil ? 1 : 0)
        .allowsHitTesting(vm.detent == .collapsed || vm.selected != nil)
        .alongAnimation(value: vm.detent)
    }

    private var discoverySheet: some View {
        AlongBottomSheet(detent: $vm.detent, visibleHeight: $vm.sheetHeight) {
            HStack(alignment: .firstTextBaseline) {
                Text("Happening around you")
                    .font(AlongFont.heading)
                    .foregroundStyle(AlongColor.textPrimary)
                Spacer()
                Text(vm.activities.isEmpty ? "" : "\(vm.activities.count) \(vm.activities.count == 1 ? "plan" : "plans")")
                    .font(AlongFont.subhead)
                    .foregroundStyle(AlongColor.textTertiary)
            }
        } content: {
            if vm.activities.isEmpty {
                let e = vm.emptyState
                ScrollView {
                    AlongEmptyState(title: e.title, message: e.message, actionTitle: e.action) { vm.startCreating(e.kind) }
                        .padding(.top, AlongSpacing.lg)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: AlongSpacing.sm) {
                        ForEach(vm.activities) { activity in
                            Button { vm.open(activity) } label: {
                                AlongActivityCard(activity: activity, host: vm.host(of: activity), now: store.now)
                            }
                            .buttonStyle(AlongPressStyle(scale: 0.985))
                        }
                    }
                    .padding(.horizontal, AlongSpacing.gutter)
                    .padding(.top, AlongSpacing.xs)
                    .padding(.bottom, AlongSpacing.xl)
                }
            }
        }
    }
}
