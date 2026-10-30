import SwiftUI

/// Resolves private-bucket avatar paths to short-lived signed URLs, caching them until shortly before expiry.
@MainActor @Observable
final class AvatarLoader {
    private struct Entry { let url: URL; let expires: Date }
    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private let sign: @Sendable (String) async throws -> URL

    init(sign: @escaping @Sendable (String) async throws -> URL) { self.sign = sign }

    func url(for path: String) async -> URL? {
        if let hit = cache[path], hit.expires > .now { return hit.url }
        if let task = inflight[path] { return await task.value }
        let task = Task { [sign] () -> URL? in try? await sign(path) }
        inflight[path] = task
        let url = await task.value
        inflight[path] = nil
        if let url { cache[path] = Entry(url: url, expires: .now.addingTimeInterval(50 * 60)) }
        return url
    }

    func invalidate(_ path: String) { cache[path] = nil }
}

private struct AvatarLoaderKey: EnvironmentKey { static let defaultValue: AvatarLoader? = nil }
extension EnvironmentValues {
    var avatarLoader: AvatarLoader? {
        get { self[AvatarLoaderKey.self] }
        set { self[AvatarLoaderKey.self] = newValue }
    }
}
