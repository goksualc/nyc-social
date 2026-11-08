import SwiftUI
import MapKit
import Observation

/// State for "Where are you walking?". All matching happens in PostGIS; this only builds the MapKit route, sends it once per
/// distinct search (debounced, cached) and holds what comes back.
@MainActor @Observable
final class RouteSearchModel {
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    var from: Place?
    var to: Place?
    var corridor: Double = 500
    private(set) var route: RoutePreview?
    private(set) var matches: [RouteMatch] = []
    private(set) var phase: Phase = .idle
    /// True once Find Walks ran: the navy route stays on the map and the results sheet can be reopened.
    private(set) var isActive = false

    private var task: Task<Void, Never>?
    private var cache: [String: [RouteMatch]] = [:]

    var canSearch: Bool { from != nil && to != nil && from?.coordinate != to?.coordinate }

    func clear() {
        task?.cancel()
        from = nil; to = nil; route = nil; matches = []; phase = .idle; isActive = false
    }

    func swapEnds() { swap(&from, &to) }

    /// Runs the search. `debounce` is used when the corridor slider moves, so dragging doesn't fire a request per tick.
    func find(store: AppStore, dateInterval: DateInterval?, debounce: Bool = false) {
        guard let from, let to, canSearch else { return }
        task?.cancel()
        isActive = true
        phase = .loading
        task = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(450)); if Task.isCancelled { return } }
            let preview = await RouteService.walkingRoute(from: from.coordinate, to: to.coordinate)
            if Task.isCancelled { return }
            route = preview
            let key = Self.key(from: from, to: to, corridor: corridor, day: dateInterval)
            if let hit = cache[key] { matches = hit; phase = .loaded; return }
            do {
                let found = try await store.searchAlongRoute(RouteSearchQuery(
                    route: preview.coordinates, corridorMeters: corridor, from: dateInterval?.start, to: dateInterval?.end))
                if Task.isCancelled { return }
                cache[key] = found
                matches = found
                phase = .loaded
            } catch {
                if Task.isCancelled || ErrorPresenter.map(error) == .cancelled { return }
                phase = .failed(ErrorPresenter.message(for: error, fallback: "Couldn't search along that route. Try again."))
            }
        }
    }

    private static func key(from: Place, to: Place, corridor: Double, day: DateInterval?) -> String {
        func r(_ c: Coordinate) -> String { String(format: "%.4f,%.4f", c.latitude, c.longitude) }
        return "\(r(from.coordinate))>\(r(to.coordinate))|\(Int(corridor))|\(day.map { "\($0.start.timeIntervalSince1970)" } ?? "any")"
    }
}

/// The glass entry point on the map.
struct RouteSearchPill: View {
    let model: RouteSearchModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AlongSpacing.xs) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 15, weight: .semibold))
                Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if model.isActive {
                    Text("\(model.matches.count)").font(.caption.weight(.bold)).foregroundStyle(AlongColor.navy)
                        .padding(.horizontal, 8).frame(minHeight: 22).background(AlongColor.lime, in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AlongSpacing.md)
            .frame(minHeight: 46)
            .alongGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AlongSpacing.md)
        .accessibilityLabel(model.isActive ? "Route search: \(label). Open results" : "Where are you walking?")
    }

    private var label: String {
        if model.isActive, let f = model.from, let t = model.to { return "\(f.name) → \(t.name)" }
        return "Where are you walking?"
    }
}

/// From / To, Find Walks, and the "Walks along your route" results.
struct RouteSearchSheet: View {
    let model: RouteSearchModel
    let dateInterval: DateInterval?
    let dateLabel: String?
    let onSelect: (Activity) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picking: Slot?

    enum Slot: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlongSpacing.md) {
                    VStack(spacing: AlongSpacing.xs) {
                        endpoint("From", place: model.from, slot: .from)
                        endpoint("To", place: model.to, slot: .to)
                    }
                    if let dateLabel {
                        Text("Only walks on \(dateLabel)").font(AlongFont.caption).foregroundStyle(AlongColor.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("How far off my route").font(AlongFont.label).foregroundStyle(AlongColor.textTertiary)
                            Spacer()
                            Text("\(Int(model.corridor)) m").font(AlongFont.subheadEmphasis).foregroundStyle(AlongColor.textPrimary)
                        }
                        Slider(value: Bindable(model).corridor, in: 250...1000, step: 50) { editing in
                            if !editing, model.isActive { model.find(store: store, dateInterval: dateInterval, debounce: true) }
                        }
                        .tint(AlongColor.navy)
                    }
                    AlongButton(title: "Find Walks", symbol: "magnifyingglass", isLoading: model.phase == .loading) {
                        model.find(store: store, dateInterval: dateInterval)
                    }
                    .disabled(!model.canSearch)
                    results
                }
                .padding(AlongSpacing.gutter)
            }
            .alongScreenBackground()
            .navigationTitle("Where are you walking?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if model.isActive || model.from != nil || model.to != nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("Clear") { model.clear() } }
                }
            }
        }
        .sheet(item: $picking) { slot in
            PlaceSearchView(title: slot == .from ? "Starting point" : "Destination") { place in
                if slot == .from { model.from = place } else { model.to = place }
            }
            .presentationDetents([.large])
        }
    }

    private func endpoint(_ title: String, place: Place?, slot: Slot) -> some View {
        Button { picking = slot } label: {
            HStack {
                Text(title).font(AlongFont.label).foregroundStyle(AlongColor.textTertiary).frame(width: 44, alignment: .leading)
                Text(place?.name ?? "Search NYC").font(AlongFont.body)
                    .foregroundStyle(place == nil ? AlongColor.textTertiary : AlongColor.textPrimary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AlongColor.textTertiary)
            }
            .padding(.horizontal, AlongSpacing.md)
            .frame(minHeight: AlongSize.button)
            .background(AlongColor.white, in: RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AlongRadius.control, style: .continuous).stroke(AlongColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(place?.name ?? "not set")")
    }

    @ViewBuilder private var results: some View {
        switch model.phase {
        case .idle: EmptyView()
        case .loading:
            HStack { ProgressView(); Text("Looking along your route…").font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary) }
                .frame(maxWidth: .infinity).padding(.top, AlongSpacing.md)
        case .failed(let message):
            Text(message).font(AlongFont.subhead).foregroundStyle(AlongColor.destructive)
        case .loaded:
            VStack(alignment: .leading, spacing: AlongSpacing.sm) {
                Text("Walks along your route").font(AlongFont.headline).foregroundStyle(AlongColor.textPrimary)
                if model.matches.isEmpty {
                    Text("No walks run along this route yet. Try a wider distance, or create one.")
                        .font(AlongFont.subhead).foregroundStyle(AlongColor.textTertiary)
                }
                ForEach(model.matches) { match in
                    Button { onSelect(match.activity); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AlongActivityCard(activity: match.activity, host: match.host, now: store.now)
                            if !match.labels.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(match.labels, id: \.self) { l in
                                        Text(l).font(AlongFont.label).foregroundStyle(AlongColor.navy)
                                            .padding(.horizontal, 10).padding(.vertical, 4).background(AlongColor.surface, in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, AlongSpacing.xs)
        }
    }
}

