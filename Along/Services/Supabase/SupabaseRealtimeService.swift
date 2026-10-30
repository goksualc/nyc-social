import Foundation
import Supabase

/// One channel per signed-in user with four RLS-scoped listeners. Realtime evaluates each table's SELECT policy per
/// subscriber, so clients only ever receive rows they could query themselves:
///  - `join_requests`  (requester's own + requests for plans they host)     → requestsChanged
///  - `messages` INSERT (conversations they're in, not blocked)             → message
///  - `activities`     filtered to plans they host                          → activityChanged
///  - `conversation_participants` INSERT for them                           → conversationsChanged
/// Guests are told about edits/cancellations through their own `join_requests` rows (the RPCs touch them),
/// so nobody subscribes to every activity in Manhattan.
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
        let messages = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        let activities = channel.postgresChange(AnyAction.self, schema: "public", table: "activities",
                                                filter: .eq("creator_id", value: userID))
        let participants = channel.postgresChange(InsertAction.self, schema: "public", table: "conversation_participants",
                                                  filter: .eq("user_id", value: userID))
        let decoder = manager.decoder
        self.channel = channel

        tasks = [
            Task { for await _ in requests { continuation.yield(.requestsChanged) } },
            Task { for await _ in activities { continuation.yield(.activityChanged) } },
            Task { for await _ in participants { continuation.yield(.conversationsChanged) } },
            Task {
                for await insert in messages {
                    if let row = try? insert.decodeRecord(as: MessageRow.self, decoder: decoder) { continuation.yield(.message(row.message)) }
                }
            },
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
