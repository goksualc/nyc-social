import CoreLocation
import Observation
import UIKit

/// Collects GPS fixes for ONE explicitly started walk.
///
/// - Uses `CLLocationUpdate.liveUpdates(.fitness)` plus a `CLBackgroundActivitySession`, so updates keep flowing with the
///   screen locked while the walk is active (needs the `location` background mode and When-In-Use authorization).
///   The blue status-bar pill is iOS's own indicator that tracking is running.
/// - Never started outside a walk; `stop()` ends the background session and the update stream immediately.
/// - Only real fixes are accepted. Nothing is simulated, and nothing is filled in when GPS goes quiet.
@MainActor @Observable
final class WalkLocationTracker {
    private(set) var latest: CLLocation?
    private(set) var lastFixAt: Date?
    private(set) var distanceMeters: Double = 0
    private(set) var isTracking = false
    /// True while iOS reports it can't produce a location (tunnel, indoors, permission pulled).
    private(set) var isUnavailable = false
    private(set) var permissionRevoked = false

    /// Called for every accepted fix.
    var onFix: ((CLLocation) -> Void)?

    private var task: Task<Void, Never>?
    private var background: CLBackgroundActivitySession?
    private var previous: CLLocation?

    func start() {
        guard !isTracking else { return }
        isTracking = true
        permissionRevoked = false
        background = CLBackgroundActivitySession()
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    // iOS 18 reports why updates stopped; on iOS 17 the app watches the authorization status instead.
                    if #available(iOS 18.0, *), update.authorizationDenied || update.authorizationDeniedGlobally {
                        self.permissionRevoked = true
                        self.isUnavailable = true
                        continue
                    }
                    self.permissionRevoked = false
                    guard let location = update.location else {
                        if #available(iOS 18.0, *) { self.isUnavailable = update.locationUnavailable } else { self.isUnavailable = true }
                        continue
                    }
                    self.accept(location)
                }
            } catch {
                self?.isUnavailable = true
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        background?.invalidate()
        background = nil
        isTracking = false
    }

    /// Plausibility checks: a fresh fix, a usable accuracy, and no teleporting (> 12 m/s is not a walk).
    private func accept(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return }
        if let previous {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            let d = location.distance(from: previous)
            if dt <= 0 { return }
            if d / dt > 12 { return }
            // Only count real movement, not GPS jitter while standing still.
            if d > max(4, location.horizontalAccuracy * 0.5) { distanceMeters += d } else { latest = location; lastFixAt = .now; isUnavailable = false; onFix?(location); return }
        }
        previous = location
        latest = location
        lastFixAt = .now
        isUnavailable = false
        onFix?(location)
    }
}
