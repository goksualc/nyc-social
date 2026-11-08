import Foundation
import MapKit

/// Everything Along knows about New York City: the five borough outlines, neighbourhood names and an offline gazetteer.
/// The gazetteer keeps location search useful when MapKit search is slow or offline. The server is the authority on
/// where a walk may be; `contains` mirrors its outlines (migration 14) so the app can say no before a round trip.
enum NYCGeo {
    static let center = Coordinate(40.7300, -73.9500)

    /// Hand-traced outlines of each borough's land and near-shore water (not survey data); the same polygons as the
    /// `nyc_*` rows and the Manhattan row in `private.geo_regions`.
    static let boroughs: [(name: String, outline: [Coordinate])] = [
        ("Manhattan", [
            (40.6990, -74.0200), (40.7150, -74.0210), (40.7300, -74.0150), (40.7450, -74.0100),
            (40.7600, -74.0030), (40.7720, -73.9970), (40.7900, -73.9890), (40.8050, -73.9780),
            (40.8200, -73.9660), (40.8350, -73.9520), (40.8500, -73.9420), (40.8620, -73.9310),
            (40.8760, -73.9220), (40.8830, -73.9100), (40.8480, -73.9250), (40.8250, -73.9290),
            (40.8100, -73.9270), (40.7990, -73.9280), (40.7900, -73.9370), (40.7750, -73.9450),
            (40.7600, -73.9540), (40.7450, -73.9670), (40.7300, -73.9710), (40.7200, -73.9730),
            (40.7120, -73.9760), (40.7090, -73.9910), (40.7050, -73.9990), (40.7000, -74.0080)]),
        ("The Bronx", [
            (40.8000, -73.9350), (40.8300, -73.9300), (40.8650, -73.9300), (40.8780, -73.9300), (40.9000, -73.9270),
            (40.9170, -73.9200), (40.9150, -73.8600), (40.8990, -73.8100), (40.8900, -73.7850), (40.8700, -73.7700),
            (40.8400, -73.7700), (40.8070, -73.7850), (40.7990, -73.8300), (40.7960, -73.8800), (40.7930, -73.9200)]),
        ("Queens", [
            (40.7300, -73.9650), (40.7450, -73.9600), (40.7560, -73.9500), (40.7700, -73.9420), (40.7830, -73.9300),
            (40.7900, -73.9150), (40.7880, -73.9000), (40.7850, -73.8800), (40.7900, -73.8500), (40.7930, -73.8300), (40.7960, -73.8000),
            (40.7870, -73.7700), (40.7720, -73.7400), (40.7520, -73.7000), (40.7250, -73.7000), (40.7050, -73.7150),
            (40.6900, -73.7260), (40.6650, -73.7400), (40.6050, -73.7380), (40.5900, -73.7300), (40.5820, -73.7500),
            (40.5680, -73.8500), (40.5530, -73.9400), (40.5680, -73.9420), (40.5850, -73.9050), (40.6000, -73.8950),
            (40.6700, -73.8600), (40.6950, -73.8950), (40.7060, -73.9300)]),
        ("Brooklyn", [
            (40.7250, -73.9650), (40.7450, -73.9600), (40.7300, -73.9250), (40.6960, -73.8950), (40.6770, -73.8550),
            (40.6500, -73.8500), (40.6100, -73.8700), (40.5880, -73.8900), (40.5650, -73.9000), (40.5560, -73.9800),
            (40.5650, -74.0450), (40.6050, -74.0450), (40.6350, -74.0450), (40.6600, -74.0250), (40.6850, -74.0150),
            (40.6990, -74.0080), (40.7100, -73.9980), (40.7160, -73.9800)]),
        ("Staten Island", [
            (40.6600, -74.0750), (40.6150, -74.0500), (40.5950, -74.0500), (40.5900, -74.0600), (40.5550, -74.0900),
            (40.5350, -74.1500), (40.5050, -74.2000), (40.4850, -74.2600), (40.5200, -74.2600), (40.5400, -74.2400),
            (40.5800, -74.2000), (40.6300, -74.1900), (40.6450, -74.1600), (40.6450, -74.1300), (40.6500, -74.1000)]),
    ].map { ($0.0, $0.1.map { Coordinate($0.0, $0.1) }) }

    /// A generous box around the five boroughs and their waters, for sanity-checking live positions (not for plan locations).
    static func isNearCity(_ c: Coordinate) -> Bool {
        (40.45...40.96).contains(c.latitude) && (-74.32...(-73.65)).contains(c.longitude)
    }

    static func contains(_ c: Coordinate) -> Bool { borough(of: c) != nil }

    /// Which borough outline holds the point, if any.
    static func borough(of c: Coordinate) -> String? {
        boroughs.first { polygon($0.outline, contains: c) }?.name
    }

    private static func polygon(_ outline: [Coordinate], contains c: Coordinate) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let a = outline[i], b = outline[j]
            if (a.latitude > c.latitude) != (b.latitude > c.latitude),
               c.longitude < (b.longitude - a.longitude) * (c.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Region used to bias MapKit search and to bound the map camera: all five boroughs.
    static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7100, longitude: -73.9700),
        span: MKCoordinateSpan(latitudeDelta: 0.52, longitudeDelta: 0.66))

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
        // Brooklyn
        ("Williamsburg", .init(40.7081, -73.9571)), ("Greenpoint", .init(40.7304, -73.9515)), ("DUMBO", .init(40.7033, -73.9890)),
        ("Brooklyn Heights", .init(40.6960, -73.9936)), ("Park Slope", .init(40.6710, -73.9814)), ("Prospect Park", .init(40.6602, -73.9690)),
        ("Bushwick", .init(40.6944, -73.9213)), ("Bed-Stuy", .init(40.6872, -73.9418)), ("Crown Heights", .init(40.6694, -73.9442)),
        ("Coney Island", .init(40.5755, -73.9707)), ("Bay Ridge", .init(40.6264, -74.0299)), ("Sunset Park", .init(40.6453, -74.0124)),
        ("Red Hook", .init(40.6734, -74.0083)), ("Brighton Beach", .init(40.5776, -73.9617)), ("Flatbush", .init(40.6409, -73.9594)),
        // Queens
        ("Astoria", .init(40.7644, -73.9235)), ("Long Island City", .init(40.7447, -73.9485)), ("Flushing", .init(40.7675, -73.8331)),
        ("Jackson Heights", .init(40.7557, -73.8831)), ("Forest Hills", .init(40.7185, -73.8448)), ("Jamaica", .init(40.7027, -73.7890)),
        ("Rockaway Beach", .init(40.5834, -73.8160)), ("Sunnyside", .init(40.7433, -73.9196)), ("Flushing Meadows", .init(40.7466, -73.8408)),
        ("Bayside", .init(40.7686, -73.7771)), ("Ridgewood", .init(40.7043, -73.9018)),
        // The Bronx
        ("Riverdale", .init(40.8910, -73.9140)), ("Fordham", .init(40.8610, -73.8900)), ("Belmont", .init(40.8546, -73.8880)),
        ("Pelham Bay", .init(40.8528, -73.8280)), ("Kingsbridge", .init(40.8815, -73.9020)), ("Concourse", .init(40.8296, -73.9262)),
        ("Bronx Zoo", .init(40.8506, -73.8770)), ("City Island", .init(40.8468, -73.7864)), ("Hunts Point", .init(40.8130, -73.8800)),
        ("Mott Haven", .init(40.8090, -73.9229)),
        // Staten Island
        ("St. George", .init(40.6437, -74.0735)), ("Stapleton", .init(40.6270, -74.0770)), ("Great Kills", .init(40.5540, -74.1510)),
        ("Tottenville", .init(40.5080, -74.2430)), ("New Dorp", .init(40.5740, -74.1160)), ("Port Richmond", .init(40.6350, -74.1370)),
        ("Snug Harbor", .init(40.6445, -74.1020)), ("Todt Hill", .init(40.5950, -74.1100)),
    ]

    static func neighborhood(near c: Coordinate) -> String {
        neighborhoods.min { $0.coordinate.distance(to: c) < $1.coordinate.distance(to: c) }?.name ?? "New York City"
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
        ("Penn Station", 40.7506, -73.9935, false),
        ("Brooklyn Bridge Park", 40.7003, -73.9965, false), ("Prospect Park (Brooklyn)", 40.6602, -73.9690, false),
        ("Coney Island Boardwalk", 40.5723, -73.9780, false), ("McCarren Park", 40.7203, -73.9516, false),
        ("Domino Park", 40.7142, -73.9680, false), ("Brooklyn Botanic Garden", 40.6694, -73.9625, false),
        ("Astoria Park", 40.7790, -73.9220, false), ("Flushing Meadows–Corona Park", 40.7466, -73.8408, false),
        ("Gantry Plaza State Park", 40.7466, -73.9558, false), ("Forest Park (Queens)", 40.7000, -73.8500, false),
        ("Rockaway Beach Boardwalk", 40.5834, -73.8160, false),
        ("Yankee Stadium", 40.8296, -73.9262, false), ("Pelham Bay Park", 40.8650, -73.8100, false),
        ("New York Botanical Garden", 40.8620, -73.8770, false), ("Van Cortlandt Park", 40.8970, -73.8900, false),
        ("Staten Island Ferry Terminal", 40.6437, -74.0735, false), ("Snug Harbor Cultural Center", 40.6445, -74.1020, false),
        ("Greenbelt (Staten Island)", 40.5950, -74.1100, false), ("Great Kills Park", 40.5500, -74.1300, false), ("Fifth Avenue", 40.7527, -73.9772, true),
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
}
