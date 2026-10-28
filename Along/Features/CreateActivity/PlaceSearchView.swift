import SwiftUI

/// Searchable, Manhattan-only place picker.
struct PlaceSearchView: View {
    let mode: PlaceSearchModel.Mode
    let title: String
    let onSelect: (Place) -> Void

    @State private var model: PlaceSearchModel
    @State private var query = ""
    @State private var isResolving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(mode: PlaceSearchModel.Mode, title: String, onSelect: @escaping (Place) -> Void) {
        self.mode = mode
        self.title = title
        self.onSelect = onSelect
        _model = State(initialValue: PlaceSearchModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: AlongSpacing.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AlongColor.textSecondary)
                    TextField(mode == .cafes ? "Search cafés in Manhattan" : "Search streets and places in Manhattan", text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if isResolving || model.isSearching { ProgressView().controlSize(.small) }
                    else if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(AlongColor.textSecondary)
                                .frame(width: AlongSize.minTouch, height: AlongSize.minTouch)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, AlongSpacing.md)
                .frame(minHeight: AlongSize.minTouch + 4)
                .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
                .padding(.horizontal, AlongSpacing.gutter)
                .padding(.top, AlongSpacing.xs)

                if let error {
                    Text(error).font(AlongFont.caption).foregroundStyle(AlongColor.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AlongSpacing.gutter).padding(.top, AlongSpacing.xs)
                }

                if model.suggestions.isEmpty {
                    Text(query.isEmpty ? "Try “72nd”, “Bryant Park” or “West Village”." : (model.isSearching ? "" : "No matches in Manhattan."))
                        .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                        .frame(maxWidth: .infinity).padding(AlongSpacing.xl)
                    Spacer()
                } else {
                    List(model.suggestions) { s in
                        Button { choose(s) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(AlongFont.bodyEmphasis).foregroundStyle(AlongColor.textPrimary)
                                if !s.subtitle.isEmpty { Text(s.subtitle).font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary) }
                            }
                            .frame(maxWidth: .infinity, minHeight: AlongSize.minTouch, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(AlongColor.offWhite)
                        .listRowSeparatorTint(AlongColor.border)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .alongScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .onChange(of: query) { _, q in error = nil; model.search(q) }
            .onAppear { focused = true }
        }
    }

    private func choose(_ suggestion: PlaceSearchModel.Suggestion) {
        Haptics.light()
        isResolving = true
        error = nil
        Task {
            defer { isResolving = false }
            do {
                let place = try await model.resolve(suggestion)
                guard ManhattanGeo.contains(place.coordinate) else { throw AlongError.outsideManhattan }
                onSelect(place)
                dismiss()
            } catch {
                self.error = (error as? AlongError)?.errorDescription ?? "Couldn't find that place. Try another."
            }
        }
    }
}
