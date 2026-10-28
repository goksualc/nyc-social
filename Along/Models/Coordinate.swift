import CoreLocation
import MapKit

/// Codable, Sendable coordinate so models can round-trip to a backend (e.g. Supabase) unchanged.
struct Coordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(coordinate.latitude, coordinate.longitude)
    }

    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    func distance(to other: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// Snapped to a coarse grid (~250 m). This is what the public sees instead of an exact point.
    var approximate: Coordinate {
        func snap(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
        return Coordinate(snap(latitude, 0.0025), snap(longitude, 0.0030))
    }
}
