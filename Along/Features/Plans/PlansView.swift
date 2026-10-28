import SwiftUI

struct PlansView: View {
    @State private var vm: PlansViewModel
    @Environment(AppStore.self) private var store
    @Environment(\.selectTab) private var selectTab

    init(store: AppStore) { _vm = State(initialValue: PlansViewModel(store: store)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    Text("Your Plans")
                        .font(AlongFont.screenTitle)
                        .foregroundStyle(AlongColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, AlongSpacing.sm)

                    AlongSegmentedControl(options: ["Upcoming", "Past"], selection: $vm.segment)

                    if vm.items.isEmpty {
                        AlongEmptyState(
                            title: vm.segment == 0 ? "No plans yet." : "Nothing in the past yet.",
                            message: vm.segment == 0 ? "Find something on the map, or make a plan of your own." : "Plans you've hosted or joined will end up here.",
                            actionTitle: vm.segment == 0 ? "Explore Manhattan" : nil) { selectTab(0) }
                            .padding(.top, AlongSpacing.xl)
                    } else {
                        LazyVStack(spacing: AlongSpacing.sm) {
                            ForEach(vm.items) { item in
                                NavigationLink(value: AlongRoute.activity(item.id)) {
                                    AlongActivityCard(activity: item.activity, host: vm.host(of: item), now: store.now,
                                                      statusText: vm.status(for: item), hostLabel: vm.hostLabel(for: item),
                                                      actionTitle: vm.actionTitle(for: item))
                                        .opacity(vm.segment == 1 ? 0.8 : 1)
                                }
                                .buttonStyle(AlongPressStyle(scale: 0.985))
                                .transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.bottom, AlongSpacing.xl)
                .alongAnimation(value: vm.items.map(\.id))
            }
            .alongScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .alongDestinations()
        }
    }
}
