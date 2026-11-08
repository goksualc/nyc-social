import SwiftUI
import MapKit

/// The immersive New York City map: real walks as floating pins, lime route highlights, glass controls, and a white sheet for the
/// selected walk. Data, filters, joining and navigation are the existing ones; this is the presentation layer.
struct ExploreView: View {
    @State private var vm: ExploreViewModel
    @Environment(AppStore.self) private var store
    @Environment(TabChrome.self) private var chrome
    @Environment(\.selectTab) private var selectTab
    private let location: LocationService
    @State private var joining = false
    @State private var hostProfile: IDItem?
    @State private var routeSearch = RouteSearchModel()
    @State private var showRouteSearch = false
    @Namespace private var mapScope

    init(store: AppStore, location: LocationService) {
        _vm = State(initialValue: ExploreViewModel(store: store, location: location))
        self.location = location
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 190).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: AlongSpacing.xs) {
                header
                if vm.selected == nil {
                    ExploreFilterBar(vm: vm).transition(.opacity.combined(with: .move(edge: .top)))
                    RouteSearchPill(model: routeSearch) { showRouteSearch = true }.transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            mapControls
            if vm.selected == nil { statusPill.padding(.bottom, 96) }
            if let selected = vm.selected { card(for: selected) }
        }
        .background(AlongColor.navy)
        .mapScope(mapScope)
        .onChange(of: vm.selected?.id) { _, id in chrome.isHidden = id != nil }   // the bar steps aside only while a card is actually showing
        .onAppear { chrome.isHidden = vm.selected != nil }
        .alongAnimation(value: vm.selectedID)
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

        .sheet(isPresented: $showRouteSearch) {
            RouteSearchSheet(model: routeSearch, dateInterval: ExploreViewModel.dayInterval(for: vm.dateFilter, now: store.now),
                             dateLabel: vm.dateFilter == .all ? nil : vm.label(for: vm.dateFilter)) { vm.select($0) }
                .alongToasts()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
        .sheet(isPresented: $vm.isClusterOpen) {
            ClusterWalksSheet(vm: vm)
                .alongToasts()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
        .sheet(item: $hostProfile) { item in
            UserProfileSheet(userID: item.id)
                .presentationCornerRadius(AlongRadius.sheet)
        }
        .sheet(isPresented: $vm.isCreating) {
            CreateActivityFlow()
                .alongToasts()
                .presentationCornerRadius(AlongRadius.sheet)
                .presentationBackground(AlongColor.offWhite)
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $vm.camera, bounds: ExploreViewModel.bounds, scope: mapScope) {
            if location.isAuthorized && store.settings.useLocationToCenterMap { UserAnnotation() }

            // The selected walk's route: soft halo + lime line, from MapKit directions (or the saved route for members).
            if let walk = vm.selected, let route = vm.selectedRoute {
                let line = route.coordinates.map(\.cl)
                MapPolyline(coordinates: line).stroke(AlongColor.lime.opacity(0.28), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line).stroke(AlongColor.lime, style: route.isEstimate
                    ? StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 9]) : StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                Annotation("Start", coordinate: walk.walk.from.coordinate.cl, anchor: .center) {
                    Circle().fill(AlongColor.lime).frame(width: 16, height: 16).overlay(Circle().stroke(AlongColor.navy, lineWidth: 3))
                }
                Annotation("End", coordinate: walk.walk.to.coordinate.cl, anchor: .center) {
                    Circle().fill(.white).frame(width: 16, height: 16).overlay(Circle().stroke(AlongColor.lime, lineWidth: 4))
                }
            }


            // The searched route, drawn in navy with a pale halo so it reads on the imagery.
            if routeSearch.isActive, let r = routeSearch.route {
                let line = r.coordinates.map(\.cl)
                MapPolyline(coordinates: line).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line).stroke(AlongColor.navy, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            ForEach(vm.mapItems) { item in
                switch item {
                case .walk(let activity):
                    Annotation("", coordinate: activity.mapCoordinate, anchor: .bottom) {
                        ActivityPin(activity: activity, host: store.host(of: activity), isSelected: vm.selectedID == activity.id)
                            .onTapGesture { vm.select(activity) }
                    }
                    .annotationTitles(.hidden)
                case .cluster(let cluster):
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        ClusterPin(count: cluster.activities.count, isSelected: vm.isHighlighted(cluster))
                            .contentShape(Circle())
                            .onTapGesture { vm.openCluster(cluster) }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        // Imagery with realistic elevation gives the aerial, 3D city look on a device (the Simulator draws it flat).
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .onEnd) { context in vm.regionChanged(context.region) }
        .task { await vm.reload() }
        .onTapGesture { vm.deselect() }
        .ignoresSafeArea()
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: AlongSpacing.xs) {
            AlongLogo(variant: .white, width: 104)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            Spacer()
            GlassCircleButton(symbol: "bell", label: "Messages and requests", badge: store.pendingIncomingCount > 0) { selectTab(2) }
            Menu {
                Button("Create a walk", systemImage: "plus") { vm.startCreating() }
                Button("Show my location", systemImage: "location") { Task { await vm.locateMe() } }
                Button("Reset the map", systemImage: "scope") { alongWithAnimation(.smooth(duration: 0.9)) { vm.camera = ExploreViewModel.overview } }
                Button("Your profile", systemImage: "person") { selectTab(3) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).alongGlass(in: Circle())
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, AlongSpacing.md)
        .padding(.top, AlongSpacing.xs)
    }

    private var mapControls: some View {
        VStack(spacing: AlongSpacing.xs) {
            MapCompass(scope: mapScope).mapControlVisibility(.visible)
            GlassCircleButton(symbol: "location.fill", label: "Show my location") { Task { await vm.locateMe() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, AlongSpacing.md)
        .padding(.top, 126)
        .opacity(vm.selected == nil ? 1 : 0)
        .allowsHitTesting(vm.selected == nil)
    }

    /// Loading, error and "nothing here" states as one small floating pill instead of a list sheet.
    @ViewBuilder private var statusPill: some View {
        if let error = vm.loadError {
            pill(error, action: ("Try again", { Task { await store.retryDiscovery() } }))
        } else if vm.activities.isEmpty && vm.isLoading {
            HStack(spacing: 8) { ProgressView().tint(.white); Text("Finding walks…").font(.subheadline.weight(.semibold)).foregroundStyle(.white) }
                .padding(.horizontal, 16).frame(minHeight: 44).alongGlass()
        } else if vm.activities.isEmpty {
            let e = vm.emptyState
            pill(e.title, action: (e.action ?? "Create a Walk", { vm.startCreating() }))
        }
    }

    private func pill(_ text: String, action: (String, () -> Void)) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            Button(action: action.1) {
                Text(action.0).font(.subheadline.weight(.bold)).foregroundStyle(AlongColor.navy)
                    .padding(.horizontal, 12).frame(minHeight: 34).background(AlongColor.lime, in: Capsule())
            }
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 5)
        .alongGlass()
        .padding(.horizontal, AlongSpacing.md)
    }

    // MARK: Selected walk

    private func card(for selected: Activity) -> some View {
        ActivityPreviewCard(
            activity: selected, host: vm.host(of: selected), guests: selected.participantIDs.compactMap { store.user($0) },
            role: store.role(in: selected), isHost: store.isHost(selected), route: vm.selectedRoute,
            now: store.now, isWorking: joining,
            onPrimary: { Task { joining = true; await store.requestToJoin(selected); joining = false } },
            onOpen: { vm.open(selected) },
            onHost: { hostProfile = IDItem(id: selected.hostID) },
            onClose: { vm.deselect() })
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
