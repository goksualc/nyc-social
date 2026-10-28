import Foundation

/// A location chosen by a host. `coordinate`/`name` are exact; the backend (or its mock) swaps in
/// approximate values before sending an activity to anyone who has not been accepted.
struct Place: Hashable, Codable, Sendable {
    var name: String
    /// General neighbourhood, e.g. "SoHo". Always safe to show publicly.
    var area: String
    var coordinate: Coordinate
    /// Streets and intersections are public-safe labels; named venues are not.
    var isStreet: Bool = false

    /// What anyone may see.
    var publicLabel: String { isStreet && !name.isEmpty ? name : area }

    /// What a non-member receives from the server.
    func redacted() -> Place {
        Place(name: isStreet ? name : "", area: area, coordinate: coordinate.approximate, isStreet: isStreet)
    }
}
