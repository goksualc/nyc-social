import Foundation

/// "Where are you walking?" — the route a person wants company on, and how wide a corridor around it counts as "along".
struct RouteSearchQuery: Sendable, Equatable {
    var route: [Coordinate]
    var corridorMeters: Double = 500
    var from: Date?
    var to: Date?
    var limit = 30
}

/// A walk found along a searched route, with the numbers the server measured. Labels are derived only from those numbers.
struct RouteMatch: Identifiable, Sendable, Equatable {
    var activity: Activity
    var host: User
    /// Share of the walk's own length that runs inside the corridor (0–1).
    var overlap: Double
    var routeDistanceMeters: Double
    var directionDiffDegrees: Double
    var startsNear: Bool
    var endsNear: Bool
    var score: Double
    var id: ID { activity.id }

    /// At most two honest badges; nothing is shown that the measurements don't support.
    var labels: [String] {
        var out: [String] = []
        if overlap >= 0.8 { out.append("Follows your route") }
        else if overlap >= 0.5 { out.append("Shares \(Int((overlap * 100).rounded()))% of your route") }
        if startsNear && endsNear { out.append("Starts and ends near you") }
        else if startsNear { out.append("Starts near you") }
        else if endsNear { out.append("Ends near your destination") }
        if out.count < 2, overlap >= 0.3, directionDiffDegrees <= 30 { out.append("Same direction") }
        return Array(out.prefix(2))
    }
}
