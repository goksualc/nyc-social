import CoreLocation
import Observation

/// Thin CoreLocation wrapper. Permission is only requested when the person taps "locate me".
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus
    private(set) var lastLocation: Coordinate?
    private var pendingLocate: ((Coordinate?) -> Void)?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // approximate is plenty
    }

    var isPrecise: Bool { manager.accuracyAuthorization == .fullAccuracy }
    var canAskForPermission: Bool { status == .notDetermined }

    /// Onboarding / walk start: shows the system "While Using the App" prompt. Never asks for Always.
    func requestWhenInUse() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// A live walk works best with precise location. When the person chose approximate, this asks (once, with a reason)
    /// for *temporary* precise access; the system decides whether to show it.
    func requestTemporaryPrecise() async {
        guard isAuthorized, manager.accuracyAuthorization == .reducedAccuracy else { return }
        try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "LiveWalk")
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }

    /// Resolves with the current approximate location, asking for permission first if needed.
    func locate() async -> Coordinate? {
        guard !isDenied else { return nil }
        return await withCheckedContinuation { continuation in
            pendingLocate?(nil)
            pendingLocate = { continuation.resume(returning: $0) }
            if status == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if self.isAuthorized, self.pendingLocate != nil { self.manager.requestLocation() }
            else if self.isDenied { self.finish(nil) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.lastLocation = Coordinate(c)
            self.finish(Coordinate(c))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ value: Coordinate?) {
        pendingLocate?(value)
        pendingLocate = nil
    }
}
