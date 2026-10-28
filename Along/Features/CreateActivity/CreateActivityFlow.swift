import SwiftUI

/// Resolves the store, then owns the view model for the whole create flow.
struct CreateActivityFlow: View {
    var initialKind: ActivityKind?
    @Environment(AppStore.self) private var store

    var body: some View { CreateActivityRoot(store: store, initialKind: initialKind) }
}

private struct CreateActivityRoot: View {
    @State private var vm: CreateActivityViewModel
    @State private var path: [ActivityKind]
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, initialKind: ActivityKind?) {
        _vm = State(initialValue: CreateActivityViewModel(store: store))
        _path = State(initialValue: initialKind.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ActivityTypePicker { kind in path.append(kind) }
                .alongScreenBackground()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                            .accessibilityLabel("Close")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: ActivityKind.self) { kind in
                    switch kind {
                    case .walk: CreateWalkView(vm: vm) { dismiss() }
                    case .cowork: CreateCoworkView(vm: vm) { dismiss() }
                    }
                }
        }
    }
}

/// "What are you up to?" — two large, quiet cards.
private struct ActivityTypePicker: View {
    let onSelect: (ActivityKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AlongSpacing.lg) {
            Text("What are you up to?")
                .font(AlongFont.screenTitle)
                .foregroundStyle(AlongColor.textPrimary)
                .padding(.top, AlongSpacing.md)

            VStack(spacing: AlongSpacing.sm) {
                card(.walk, "Walk", "Going somewhere? Bring someone along.")
                card(.cowork, "Cowork", "Getting some work done? Find good company.")
            }
            Spacer()
        }
        .padding(.horizontal, AlongSpacing.gutter)
    }

    private func card(_ kind: ActivityKind, _ title: String, _ subtitle: String) -> some View {
        Button {
            Haptics.light()
            onSelect(kind)
        } label: {
            HStack(spacing: AlongSpacing.md) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AlongColor.navy)
                    .frame(width: 56, height: 56)
                    .background(AlongColor.surface, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(AlongColor.textPrimary)
                    Text(subtitle).font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AlongColor.textSecondary)
            }
            .padding(AlongSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .alongCard(radius: AlongRadius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(AlongPressStyle(scale: 0.985))
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
