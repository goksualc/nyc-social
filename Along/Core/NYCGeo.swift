import Foundation
import MapKit

/// Everything Along knows about Manhattan: the boundary, neighbourhood names and an offline gazetteer.
/// The gazetteer keeps location search useful when MapKit search is slow or offline.
enum ManhattanGeo {
    static let center = Coordinate(40.7580, -73.9780)

    /// Loose outline of the island (slightly generous around waterfront parks).
    static let boundary: [Coordinate] = [
        (40.6990, -74.0200), (40.7150, -74.0210), (40.7300, -74.0150), (40.7450, -74.0100),
        (40.7600, -74.0030), (40.7720, -73.9970), (40.7900, -73.9890), (40.8050, -73.9780),
        (40.8200, -73.9660), (40.8350, -73.9520), (40.8500, -73.9420), (40.8620, -73.9310),
        (40.8760, -73.9220), (40.8830, -73.9100), (40.8480, -73.9250), (40.8250, -73.9290),
        (40.8100, -73.9270), (40.7990, -73.9280), (40.7900, -73.9370), (40.7750, -73.9450),
        (40.7600, -73.9540), (40.7450, -73.9670), (40.7300, -73.9710), (40.7200, -73.9730),
        (40.7120, -73.9760), (40.7090, -73.9910), (40.7050, -73.9990), (40.7000, -74.0080),
    ].map { Coordinate($0.0, $0.1) }

    static func contains(_ c: Coordinate) -> Bool {
        var inside = false
        var j = boundary.count - 1
        for i in boundary.indices {
            let a = boundary[i], b = boundary[j]
            if (a.latitude > c.latitude) != (b.latitude > c.latitude),
               c.longitude < (b.longitude - a.longitude) * (c.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Region used to bias MapKit search and to bound the map camera.
    static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7900, longitude: -73.9700),
        span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.10))

    // MARK: Neighbourhoods

    static let neighborhoods: [(name: String, coordinate: Coordinate)] = [
        ("Financial District", .init(40.7075, -74.0090)), ("Tribeca", .init(40.7195, -74.0089)),
        ("Chinatown", .init(40.7158, -73.9970)), ("SoHo", .init(40.7233, -74.0030)),
        ("Lower East Side", .init(40.7150, -73.9843)), ("East Village", .init(40.7265, -73.9815)),
        ("West Village", .init(40.7358, -74.0036)), ("Greenwich Village", .init(40.7336, -73.9990)),
        ("Chelsea", .init(40.7465, -74.0014)), ("Flatiron", .init(40.7411, -73.9897)),
        ("Gramercy", .init(40.7368, -73.9845)), ("Murray Hill", .init(40.7479, -73.9757)),
        ("Hell's Kitchen", .init(40.7638, -73.9918)), ("Midtown", .init(40.7549, -73.9840)),
        ("Midtown East", .init(40.7553, -73.9700)), ("Lincoln Square", .init(40.7737, -73.9840)),
        ("Upper West Side", .init(40.7870, -73.9754)), ("Upper East Side", .init(40.7736, -73.9566)),
        ("Central Park", .init(40.7829, -73.9654)), ("Morningside Heights", .init(40.8100, -73.9626)),
        ("Harlem", .init(40.8116, -73.9465)), ("Washington Heights", .init(40.8417, -73.9393)),
        ("Inwood", .init(40.8677, -73.9212)),
    ]

    static func neighborhood(near c: Coordinate) -> String {
        neighborhoods.min { $0.coordinate.distance(to: c) < $1.coordinate.distance(to: c) }?.name ?? "Manhattan"
    }

    // MARK: Gazetteer

    /// Approximate position of a numbered street, interpolated along Fifth Avenue.
    static func street(_ number: Int) -> Place {
        let n = Double(number)
        let c = Coordinate(40.7360 + (n - 14) * 0.000631, -73.9929 + (n - 14) * 0.000427)
        return Place(name: "\(ordinal(number)) St", area: neighborhood(near: c), coordinate: c, isStreet: true)
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static let landmarks: [Place] = [
        ("Central Park West", 40.7794, -73.9754, true), ("Columbus Circle", 40.7681, -73.9819, true),
        ("Times Square", 40.7580, -73.9855, false), ("Bryant Park", 40.7536, -73.9832, false),
        ("Grand Central", 40.7527, -73.9772, false), ("Union Square", 40.7359, -73.9911, false),
        ("Washington Square Park", 40.7308, -73.9973, false), ("Madison Square Park", 40.7421, -73.9879, false),
        ("The High Line", 40.7480, -74.0048, false), ("Hudson Yards", 40.7536, -74.0007, false),
        ("Battery Park", 40.7033, -74.0170, false), ("Lincoln Center", 40.7725, -73.9835, false),
        ("Columbia University", 40.8075, -73.9626, false), ("Chelsea Market", 40.7424, -74.0061, false),
        ("Brooklyn Bridge (Manhattan side)", 40.7118, -74.0013, false), ("Tompkins Square Park", 40.7265, -73.9818, false),
        ("Riverside Park", 40.7960, -73.9720, false), ("The Met", 40.7794, -73.9632, false),
        ("Penn Station", 40.7506, -73.9935, false), ("Fifth Avenue", 40.7527, -73.9772, true),
        ("Broadway", 40.7580, -73.9855, true), ("Hudson River Greenway", 40.7410, -74.0100, true),
    ].map { Place(name: $0.0, area: neighborhood(near: Coordinate($0.1, $0.2)), coordinate: Coordinate($0.1, $0.2), isStreet: $0.3) }

    /// Offline matches for a typed query: numbered streets, landmarks, neighbourhoods.
    static func suggestions(matching query: String) -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var out: [Place] = []
        if let n = Int(q.prefix { $0.isNumber }), (1...125).contains(n) { out.append(street(n)) }
        out += landmarks.filter { $0.name.lowercased().contains(q) }
        out += neighborhoods.filter { $0.name.lowercased().contains(q) }
            .map { Place(name: $0.name, area: $0.name, coordinate: $0.coordinate, isStreet: false) }
        return Array(out.prefix(6))
    }

    /// Curated cafés used when MapKit returns nothing. Names are illustrative.
    static let cafes: [Place] = [
        ("Lantern Coffee", 40.7233, -74.0000), ("Sidecar Espresso", 40.7411, -73.9890),
        ("Marlow Roasters", 40.7338, -74.0050), ("Oak & Ember Café", 40.7536, -73.9840),
        ("Kettle Row", 40.7268, -73.9850), ("Hollis Coffee House", 40.7465, -74.0000),
        ("Greenhouse Café", 40.7877, -73.9750), ("Penny Lane Bakery", 40.7736, -73.9560),
        ("Morning Table", 40.7080, -74.0090), ("Quiet Cup", 40.8116, -73.9465),
    ].map { Place(name: $0.0, area: neighborhood(near: Coordinate($0.1, $0.2)), coordinate: Coordinate($0.1, $0.2)) }
}
