import Network
import Observation

/// Tracks connectivity so the UI can say "You're offline" instead of failing mysteriously.
@MainActor @Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "along.network", qos: .utility))
    }

    deinit { monitor.cancel() }
}
