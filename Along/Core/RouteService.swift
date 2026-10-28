import MapKit

struct RoutePreview: Sendable, Equatable {
    var coordinates: [Coordinate]
    var distance: CLLocationDistance
    var travelTime: TimeInterval
    /// True when MapKit couldn't be reached and this is a straight-line estimate.
    var isEstimate: Bool

    var summary: String {
        let miles = distance / 1609.344
        let minutes = max(Int((travelTime / 60).rounded()), 1)
        return String(format: "%.1f mi · %d min", miles, minutes)
    }
}

enum RouteService {
    /// Walking route between two (approximate) points, with a straight-line fallback.
    static func walkingRoute(from a: Coordinate, to b: Coordinate) async -> RoutePreview {
        let fallback = estimate(a, b)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.cl))
        request.transportType = .walking
        return await withTaskGroup(of: RoutePreview?.self) { group in
            group.addTask {
                guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
                let pts = route.polyline.points()
                let coords = (0..<route.polyline.pointCount).map { Coordinate(pts[$0].coordinate) }
                return RoutePreview(coordinates: coords, distance: route.distance, travelTime: route.expectedTravelTime, isEstimate: false)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(4))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? fallback
        }
    }

    static func estimate(_ a: Coordinate, _ b: Coordinate) -> RoutePreview {
        // Manhattan's grid makes the walked distance ~1.3x the straight line; 1.35 m/s walking pace.
        let d = a.distance(to: b) * 1.3
        return RoutePreview(coordinates: [a, b], distance: d, travelTime: d / 1.35, isEstimate: true)
    }
}
