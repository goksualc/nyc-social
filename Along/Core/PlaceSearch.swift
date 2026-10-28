import MapKit
import Observation

/// Manhattan-restricted place search. Blends instant offline gazetteer matches with MapKit results.
@MainActor @Observable
final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    enum Mode { case places, cafes }

    struct Suggestion: Identifiable {
        enum Source { case resolved(Place), completion(MKLocalSearchCompletion) }
        let id = UUID()
        let title: String
        let subtitle: String
        let source: Source
    }

    let mode: Mode
    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false
    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var localMatches: [Suggestion] = []

    init(mode: Mode) {
        self.mode = mode
        super.init()
        completer.delegate = self
        completer.region = ManhattanGeo.searchRegion
        completer.resultTypes = [.address, .pointOfInterest, .query]
        if mode == .cafes { suggestions = Self.curatedCafes(matching: "") }
    }

    func search(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .places:
            localMatches = ManhattanGeo.suggestions(matching: q).map { Suggestion(title: $0.name, subtitle: $0.area, source: .resolved($0)) }
            suggestions = localMatches
            if q.isEmpty { completer.cancel(); isSearching = false } else { completer.queryFragment = q; isSearching = true }
        case .cafes:
            suggestions = Self.curatedCafes(matching: q)
            isSearching = true
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                await self.searchCafes(q)
            }
        }
    }

    // MARK: Completer

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            let blocked = ["Brooklyn", "Queens", "Bronx", "Staten Island", ", NJ", "Jersey City", "Hoboken", "Long Island City"]
            let mapped = results
                .filter { r in !blocked.contains { r.subtitle.contains($0) } }
                .prefix(6)
                .map { Suggestion(title: $0.title, subtitle: $0.subtitle, source: .completion($0)) }
            let existing = Set(self.localMatches.map(\.title))
            self.suggestions = self.localMatches + mapped.filter { !existing.contains($0.title) }
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.isSearching = false }
    }

    // MARK: Cafés

    private static func curatedCafes(matching q: String) -> [Suggestion] {
        ManhattanGeo.cafes
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.area.localizedCaseInsensitiveContains(q) }
            .map { Suggestion(title: $0.name, subtitle: $0.area, source: .resolved($0)) }
    }

    private func searchCafes(_ q: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q.isEmpty ? "coffee shop" : "\(q) coffee"
        request.region = ManhattanGeo.searchRegion
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.cafe, .bakery])
        let curated = Self.curatedCafes(matching: q)
        do {
            let response = try await MKLocalSearch(request: request).start()
            let found: [Suggestion] = response.mapItems.compactMap { item in
                let c = Coordinate(item.placemark.coordinate)
                guard ManhattanGeo.contains(c), let name = item.name else { return nil }
                let area = ManhattanGeo.neighborhood(near: c)
                return Suggestion(title: name, subtitle: area, source: .resolved(Place(name: name, area: area, coordinate: c)))
            }
            if !Task.isCancelled { suggestions = Array((found + curated).prefix(12)) }
        } catch {
            if !Task.isCancelled { suggestions = curated }
        }
        isSearching = false
    }

    // MARK: Resolve

    /// Turns a suggestion into a concrete Manhattan place, or throws `.outsideManhattan`.
    func resolve(_ suggestion: Suggestion) async throws -> Place {
        switch suggestion.source {
        case .resolved(let place):
            return place
        case .completion(let completion):
            let response = try await MKLocalSearch(request: .init(completion: completion)).start()
            guard let item = response.mapItems.first else { throw AlongError.notFound }
            let c = Coordinate(item.placemark.coordinate)
            guard ManhattanGeo.contains(c) else { throw AlongError.outsideManhattan }
            return Self.place(from: item, fallbackTitle: completion.title, at: c)
        }
    }

    /// Street-number addresses are never kept — residential addresses must not be published.
    private static func place(from item: MKMapItem, fallbackTitle: String, at c: Coordinate) -> Place {
        let area = ManhattanGeo.neighborhood(near: c)
        let name = item.name ?? fallbackTitle
        let startsWithNumber = name.first?.isNumber == true
        if item.pointOfInterestCategory == nil || startsWithNumber {
            let street = item.placemark.thoroughfare ?? (startsWithNumber ? nil : name)
            if let street { return Place(name: street, area: area, coordinate: c, isStreet: true) }
        }
        return Place(name: name, area: area, coordinate: c, isStreet: false)
    }
}
