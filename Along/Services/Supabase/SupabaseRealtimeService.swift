import Foundation
import Supabase

/// One channel per signed-in user with four RLS-scoped listeners. Realtime evaluates each table's SELECT policy per
/// subscriber, so clients only ever receive rows they could query themselves:
///  - `join_requests`  (requester's own + requests for plans they host)     → requestsChanged
///  - `chat_pings` INSERT (conversations they're in)                        → conversationsChanged
///    (the app can't read `messages` any more; a ping carries no content and no ids, just "something happened in chat X")
///  - `activities`     filtered to plans they host                          → activityChanged
/// Guests are told about edits/cancellations through their own `join_requests` rows (the RPCs touch them),
/// so nobody subscribes to every activity in the city.
actor SupabaseRealtimeService: RealtimeService {
    private let manager: SupabaseManager
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0

    init(manager: SupabaseManager) { self.manager = manager }

    func start(userID: ID) async -> AsyncStream<RealtimeEvent> {
        await stop()                                   // never leave a previous subscription behind
        generation += 1
        let myGeneration = generation
        let (stream, continuation) = AsyncStream<RealtimeEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))

        let channel = manager.client.realtimeV2.channel("along-\(userID)")
        let requests = channel.postgresChange(AnyAction.self, schema: "public", table: "join_requests")
        let pings = channel.postgresChange(InsertAction.self, schema: "public", table: "chat_pings")
        let activities = channel.postgresChange(AnyAction.self, schema: "public", table: "activities",
                                                filter: .eq("creator_id", value: userID))
        self.channel = channel

        tasks = [
            Task { for await _ in requests { continuation.yield(.requestsChanged) } },
            Task { for await _ in activities { continuation.yield(.activityChanged) } },
            Task { for await _ in pings { continuation.yield(.conversationsChanged) } },
            // Reconnect handling: after any drop, the next return to `.subscribed` triggers a full refresh.
            Task {
                var hasBeenSubscribed = false
                for await status in channel.statusChange where status == .subscribed {
                    if hasBeenSubscribed { continuation.yield(.reconnected) }
                    hasBeenSubscribed = true
                }
            },
            // Initial subscribe, retrying with backoff until it works or this subscription is superseded.
            Task { [weak self] in
                var delay: UInt64 = 1
                while !Task.isCancelled {
                    do {
                        try await channel.subscribeWithError()
                        return
                    } catch {
                        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                        delay = min(delay * 2, 30)
                        guard let self, await self.generation == myGeneration else { return }
                    }
                }
            },
        ]
        continuation.onTermination = { _ in }
        return stream
    }

    func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        if let channel {
            await channel.unsubscribe()
            await manager.client.realtimeV2.removeChannel(channel)
        }
        channel = nil
    }
}
