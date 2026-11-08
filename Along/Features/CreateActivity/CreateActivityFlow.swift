import SwiftUI

/// Resolves the store, then owns the view model for the create flow: one screen, "Where are we walking?".
struct CreateActivityFlow: View {
    @Environment(AppStore.self) private var store

    var body: some View { CreateActivityRoot(store: store) }
}

private struct CreateActivityRoot: View {
    @State private var vm: CreateActivityViewModel
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore) {
        _vm = State(initialValue: CreateActivityViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            CreateWalkView(vm: vm) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                            .accessibilityLabel("Close")
                    }
                }
        }
    }
}
