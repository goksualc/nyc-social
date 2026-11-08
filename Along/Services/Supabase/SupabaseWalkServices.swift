import Foundation
import Supabase

/// Walk sessions, history and live positions against Supabase. Every state change is an RPC; nothing is decided on the device.

final class SupabaseWalkSessionService: WalkSessionService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    private struct P: Encodable { var pSessionId: String }
    private struct Sharing: Encodable { var pSessionId: String; var pEnabled: Bool }
    private struct Finish: Encodable { var pSessionId: String; var pDistanceM: Int? }

    func openSession(activityID: ID) async throws -> WalkSession {
        try await client.rpc("open_walk_session", params: ["p_activity_id": activityID]).execute().value
    }

    func session(activityID: ID) async throws -> WalkSession? {
        let result: WalkSession? = try await client.rpc("get_walk_session", params: ["p_activity_id": activityID]).execute().value
        return result
    }

    func setReady(sessionID: ID) async throws -> WalkSession {
        try await client.rpc("set_walk_ready", params: P(pSessionId: sessionID)).execute().value
    }

    func setSharing(sessionID: ID, enabled: Bool) async throws -> WalkSession {
        try await client.rpc("set_walk_sharing", params: Sharing(pSessionId: sessionID, pEnabled: enabled)).execute().value
    }

    func finish(sessionID: ID, distanceMeters: Int?) async throws -> WalkSession {
        try await client.rpc("finish_walk", params: Finish(pSessionId: sessionID, pDistanceM: distanceMeters)).execute().value
    }

    func endEarly(sessionID: ID) async throws -> WalkSession {
        try await client.rpc("end_walk_early", params: P(pSessionId: sessionID)).execute().value
    }
}

final class SupabaseWalkHistoryService: WalkHistoryService, @unchecked Sendable {
    private let manager: SupabaseManager
    private var client: SupabaseClient { manager.client }
    init(manager: SupabaseManager) { self.manager = manager }

    func history() async throws -> [CompletedWalk] {
        try await client.rpc("list_my_walk_history").execute().value
    }

    func stats() async throws -> WalkStats {
        try await client.rpc("my_walk_stats").execute().value
    }

    func publicStats(userID: ID) async throws -> WalkStats? {
        let stats: WalkStats? = try await client.rpc("profile_walk_stats", params: ["p_user": userID]).execute().value
        return stats
    }

    func setMemoryPrefs(sessionID: ID, showOnProfile: Bool?, revealPartner: Bool?) async throws {
        struct Prefs: Encodable { var pSessionId: String; var pShowOnProfile: Bool?; var pRevealPartner: Bool? }
        // Explicit nulls so PostgREST matches the three-argument function; the server keeps the old value for nil.
        struct Body: Encodable {
            var pSessionId: String; var pShowOnProfile: Bool?; var pRevealPartner: Bool?
            enum CodingKeys: String, CodingKey { case pSessionId, pShowOnProfile, pRevealPartner }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(pSessionId, forKey: .pSessionId)
                try c.encode(pShowOnProfile, forKey: .pShowOnProfile)
                try c.encode(pRevealPartner, forKey: .pRevealPartner)
            }
        }
        try await client.rpc("set_walk_memory_prefs", params: Body(pSessionId: sessionID, pShowOnProfile: showOnProfile, pRevealPartner: revealPartner)).execute()
    }
}

/// Positions travel over the private broadcast channel `walk:<session id>`. The database policies on `realtime.messages`
/// only let a participant who is still sharing, in a live session, join, send or receive — so revoking sharing cuts the channel.
actor SupabaseLiveWalkService: LiveWalkService {
    private let manager: SupabaseManager
    private var channel: RealtimeChannelV2?
    private var changes: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []

    init(manager: SupabaseManager) { self.manager = manager }

    func connect(sessionID: ID, myID: ID) async throws -> LiveWalkStreams {
        await disconnect()
        let client = manager.client
        let channel = client.realtimeV2.channel("walk:\(sessionID.lowercased())") { $0.isPrivate = true }
        let changes = client.realtimeV2.channel("walk-session-\(sessionID.lowercased())")
        let broadcasts = channel.broadcastStream(event: "pos")
        let rows = changes.postgresChange(AnyAction.self, schema: "public", table: "walk_sessions", filter: .eq("id", value: sessionID))
        let people = changes.postgresChange(AnyAction.self, schema: "public", table: "walk_session_participants", filter: .eq("session_id", value: sessionID))
        let status = channel.statusChange
        self.channel = channel
        self.changes = changes

        let (positions, positionsOut) = AsyncStream<LivePosition>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let (changed, changedOut) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (lost, lostOut) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        tasks = [
            Task {
                for await message in broadcasts {
                    let payload: JSONObject
                    if case .object(let inner)? = message["payload"] { payload = inner } else { payload = message }
                    guard let position = try? payload.decode(as: LivePosition.self, decoder: JSONDecoder()),
                          position.userId.lowercased() != myID.lowercased() else { continue }   // ignore my own echoes
                    positionsOut.yield(position)
                }
            },
            Task { for await _ in rows { changedOut.yield() } },
            Task { for await _ in people { changedOut.yield() } },
            Task {
                var wasSubscribed = false
                for await s in status {
                    if s == .subscribed { wasSubscribed = true }
                    else if wasSubscribed && (s == .unsubscribed) { lostOut.yield() }
                }
            },
        ]
        try await changes.subscribeWithError()
        try await channel.subscribeWithError()      // throws when the server refuses the join (not a participant / not sharing)
        return LiveWalkStreams(positions: positions, sessionChanged: changed, connectionLost: lost)
    }

    func publish(_ position: LivePosition) async {
        guard let channel, channel.status == .subscribed else { return }
        try? await channel.broadcast(event: "pos", message: position)
    }

    func disconnect() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        for c in [channel, changes].compactMap({ $0 }) {
            await c.unsubscribe()
            await manager.client.realtimeV2.removeChannel(c)
        }
        channel = nil
        changes = nil
    }
}
