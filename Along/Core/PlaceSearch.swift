import MapKit
import Observation

/// New York City place search (all five boroughs). Blends instant offline gazetteer matches with MapKit results.
@MainActor @Observable
final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        enum Source { case resolved(Place), completion(MKLocalSearchCompletion) }
        let id = UUID()
        let title: String
        let subtitle: String
        let source: Source
    }

    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false
    /// Created on the first real query, not at init. Making an `MKLocalSearchCompleter` opens an XPC connection and starts
    /// CoreLocation; doing that for every model instance (SwiftUI builds one each time the parent form redraws) is wasted work.
    private var completer: MKLocalSearchCompleter?
    private var localMatches: [Suggestion] = []
    private var settleTask: Task<Void, Never>?

    override init() { super.init() }

    private func makeCompleter() -> MKLocalSearchCompleter {
        if let completer { return completer }
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.region = NYCGeo.searchRegion
        c.resultTypes = [.address, .pointOfInterest, .query]
        completer = c
        return c
    }

    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        settleTask?.cancel()
        localMatches = NYCGeo.suggestions(matching: q).map { Suggestion(title: $0.name, subtitle: $0.area, source: .resolved($0)) }
        suggestions = localMatches
        if q.isEmpty {
            completer?.cancel()
            isSearching = false
        } else {
            makeCompleter().queryFragment = q
            isSearching = true
            // If MapKit never answers (no network, no location in the Simulator), stop the spinner; offline matches stay usable.
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { self?.isSearching = false }
            }
        }
    }

    // MARK: Completer

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            // MapKit is biased to the city, but can still offer places just over the line; those are dropped here and again on resolve.
            let blocked = [", NJ", "Jersey City", "Hoboken", "Newark", "Yonkers", "Mount Vernon", "New Rochelle", "Hempstead", "Nassau", "Westchester"]
            let mapped = results
                .filter { r in !blocked.contains { r.subtitle.contains($0) } }
                .prefix(6)
                .map { Suggestion(title: $0.title, subtitle: $0.subtitle, source: .completion($0)) }
            let existing = Set(self.localMatches.map(\.title))
            self.suggestions = self.localMatches + mapped.filter { !existing.contains($0.title) }
            self.settleTask?.cancel()
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.isSearching = false }
    }

    // MARK: Resolve

    /// Turns a suggestion into a concrete New York City place, or throws `.outsideNYC`.
    func resolve(_ suggestion: Suggestion) async throws -> Place {
        switch suggestion.source {
        case .resolved(let place):
            return place
        case .completion(let completion):
            let response = try await MKLocalSearch(request: .init(completion: completion)).start()
            guard let item = response.mapItems.first else { throw AlongError.notFound }
            let c = Coordinate(item.placemark.coordinate)
            guard NYCGeo.contains(c) else { throw AlongError.outsideNYC }
            return Self.place(from: item, fallbackTitle: completion.title, at: c)
        }
    }

    /// Street-number addresses are never kept — residential addresses must not be published.
    private static func place(from item: MKMapItem, fallbackTitle: String, at c: Coordinate) -> Place {
        let area = NYCGeo.neighborhood(near: c)
        let name = item.name ?? fallbackTitle
        let startsWithNumber = name.first?.isNumber == true
        if item.pointOfInterestCategory == nil || startsWithNumber {
            let street = item.placemark.thoroughfare ?? (startsWithNumber ? nil : name)
            if let street { return Place(name: street, area: area, coordinate: c, isStreet: true) }
        }
        return Place(name: name, area: area, coordinate: c, isStreet: false)
    }
}
