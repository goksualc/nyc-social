import SwiftUI

struct PlansView: View {
    @State private var vm: PlansViewModel
    @Environment(AppStore.self) private var store
    @Environment(\.selectTab) private var selectTab
    @State private var showCreate = false

    init(store: AppStore) { _vm = State(initialValue: PlansViewModel(store: store)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    AlongScreenHeader(title: "Walks", subtitle: "Good walks. Better conversations.")
                    searchBar
                    AlongPillRow(items: PlansViewModel.Filter.allCases, title: \.rawValue, selection: $vm.filter)

                    if vm.entries.isEmpty {
                        empty
                    } else {
                        if let featured = vm.featured { featuredCard(featured) }
                        if !vm.rest.isEmpty {
                            Text(vm.filter == .past ? "Past Walks" : "Upcoming Walks")
                                .font(AlongFont.sectionHeading).foregroundStyle(AlongColor.textPrimary).padding(.top, 6)
                            VStack(spacing: AlongSpacing.sm) {
                                ForEach(vm.rest) { entry in row(entry) }
                            }
                        }
                    }

                    AlongButton(title: "Create Walk", symbol: "plus") { showCreate = true }.padding(.top, AlongSpacing.xs)
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.top, AlongSpacing.xs)
                .padding(.bottom, AlongSpacing.xl)
                .alongAnimation(value: vm.entries.map(\.id))
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await vm.refresh() }
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .alongDestinations()
            .sheet(isPresented: $showCreate) {
                CreateActivityFlow()
                    .alongToasts()
                    .presentationCornerRadius(AlongRadius.sheet)
                    .presentationBackground(AlongColor.offWhite)
            }
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: AlongSpacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(AlongColor.textSecondary)
            TextField("Search walks, neighborhoods, or topics...", text: $vm.query)
                .submitLabel(.search).autocorrectionDisabled()
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AlongColor.textSecondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AlongSpacing.md)
        .frame(minHeight: 52)
        .background(AlongColor.white, in: Capsule())
        .overlay(Capsule().stroke(AlongColor.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: Featured

    private func featuredCard(_ entry: PlansViewModel.Entry) -> some View {
        let a = entry.activity
        return NavigationLink(value: AlongRoute.activity(a.id)) {
            ZStack(alignment: .bottomLeading) {
                WalkSnapshotView(activity: a)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.title).font(AlongFont.walkFeaturedTitle).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.8)
                    Text("\(a.walk.from.area) · \(ActivityTime.summary(a, now: vm.now, separator: ", "))")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                .padding(AlongSpacing.md)
                .padding(.trailing, 56)
                VStack {
                    HStack {
                        Label("Walk", systemImage: "figure.walk").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.navy)
                            .padding(.horizontal, 10).frame(height: 28).background(.white.opacity(0.92), in: Capsule())
                        Spacer()
                        if let badge = vm.badge(for: entry) {
                            Text(badge).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 28).background(AlongColor.navy.opacity(0.85), in: Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(AlongSpacing.sm + 2)
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(AlongColor.navy)
                    .frame(width: 46, height: 46).background(.white, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(AlongSpacing.md)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(AlongPressStyle(scale: 0.985))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.title), \(a.walk.from.area), \(ActivityTime.summary(a, now: vm.now))")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Rows

    private func row(_ entry: PlansViewModel.Entry) -> some View {
        let a = entry.activity
        let going = a.participantCount ?? a.participantIDs.count
        let miles = DistanceFormat.miles(a.walk.from.coordinate.distance(to: a.walk.to.coordinate) * 1.3)
        return NavigationLink(value: AlongRoute.activity(a.id)) {
            HStack(spacing: AlongSpacing.sm + 2) {
                WalkSnapshotView(activity: a).frame(width: 78, height: 78).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let badge = vm.badge(for: entry) {
                            Text(badge).font(.system(size: 10, weight: .bold)).foregroundStyle(AlongColor.navy).lineLimit(1)
                                .padding(.horizontal, 7).frame(height: 20).background(AlongColor.lime, in: Capsule()).padding(.bottom, 5)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(a.title).font(AlongFont.walkCardTitle).foregroundStyle(AlongColor.navy).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    Text("\(a.walk.from.area) · \(ActivityTime.summary(a, now: vm.now, separator: ", "))")
                        .font(.system(size: 13)).foregroundStyle(AlongColor.textTertiary).lineLimit(1)
                    HStack(spacing: 6) {
                        if let host = vm.host(of: entry) { AlongProfileAvatar(user: host, size: 20) }
                        Image(systemName: "person.2").font(.system(size: 11)).foregroundStyle(AlongColor.textSecondary)
                        Text(going > 0 ? "\(going) going" : vm.availability(for: entry)).font(.system(size: 12, weight: .medium))
                        Text("·").foregroundStyle(AlongColor.textSecondary)
                        Text("≈ \(miles)").font(.system(size: 12, weight: .medium))
                        if going > 0, a.isActive(at: vm.now) {
                            Text("·").foregroundStyle(AlongColor.textSecondary)
                            Text(a.spotsLabel).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x3F7D1E))
                        }
                    }
                    .foregroundStyle(AlongColor.textPrimary).lineLimit(1)
                }
            }
            .padding(AlongSpacing.sm)
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            .opacity(vm.filter == .past ? 0.85 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(AlongPressStyle(scale: 0.985))
        .transition(.opacity)
    }

    private var empty: some View {
        let searching = !vm.query.isEmpty
        return AlongEmptyState(
            title: searching ? "No walks match “\(vm.query)”." : (vm.filter == .past ? "Nothing in the past yet." : "No walks here yet."),
            message: searching ? "Try a neighborhood, a topic or a host's name." : (vm.filter == .past ? "Walks you've hosted or joined will end up here." : "Find something on the map, or start one of your own."),
            actionTitle: !searching && vm.filter != .past ? "Explore NYC" : nil) { selectTab(0) }
            .padding(.top, AlongSpacing.lg)
    }
}
