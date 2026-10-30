import Foundation
import Supabase

/// Builds the signed-in user's `AlongSnapshot` from Supabase. Everything is fetched through RLS-protected tables
/// or the secure RPCs, so the result already contains only what this user may see.
struct SupabaseSnapshotLoader: Sendable {
    let manager: SupabaseManager
    let settings = LocalSettingsStore()

    static let profileColumns = "id, username, display_name, bio, avatar_url, interests, looking_for, visibility"
    static let messageColumns = "id, conversation_id, sender_id, content, created_at"
    private var db: PostgrestClient { manager.client.schema("public") }

    func load() async throws -> AlongSnapshot {
        let uid = try manager.requireUserID()

        async let profile = SupabaseProfileService(manager: manager).loadMyProfile()
        async let cards: [ActivityCardRow] = db.rpc("list_my_activities").execute().value
        async let requestRows: [JoinRequestRow] = db.from("join_requests")
            .select("id, activity_id, requester_id, status, created_at")
            .order("created_at", ascending: false).limit(500).execute().value
        async let conversationRows: [ConversationRow] = db.from("conversations")
            .select("id, activity_id, created_at, conversation_participants(user_id)").execute().value
        async let messageRows: [MessageRow] = db.from("messages").select(Self.messageColumns)
            .order("created_at", ascending: false).limit(200).execute().value
        async let blockRows: [BlockRow] = db.from("user_blocks").select("blocked_id, blocked_display_name").execute().value

        let (me, cards_, requests_, conversations_, messages_, blocks_) =
            try await (profile, cards, requestRows, conversationRows, messageRows, blockRows)

        var activities = cards_.map { $0.activity() }
        let requests = requests_.map(\.request)

        // Hosts see who is going; everyone else only gets the count from the server.
        for i in activities.indices {
            let mine = activities[i].hostID == uid
            if mine {
                activities[i].participantIDs = requests
                    .filter { $0.activityID == activities[i].id && $0.status == .accepted }.map(\.requesterID)
            }
        }

        // Exact places + meeting details, only for plans I host or have been accepted into.
        let preciseIDs = cards_.filter { $0.viewerIsCreator || $0.viewerIsParticipant }.map(\.id)
        if !preciseIDs.isEmpty {
            let details: [PrivateDetailsRow] = try await db
                .rpc("get_private_activity_details", params: ["p_activity_ids": preciseIDs]).execute().value
            let byID = Dictionary(details.map { ($0.activityId, $0) }, uniquingKeysWith: { a, _ in a })
            for i in activities.indices { byID[activities[i].id]?.apply(to: &activities[i]) }
        }

        // People: profiles I'm allowed to read, with card/host and block snapshots as fallbacks.
        var wanted = Set(activities.map(\.hostID))
        wanted.formUnion(requests.map(\.requesterID))
        wanted.formUnion(conversations_.flatMap { $0.conversationParticipants.map(\.userId) })
        wanted.remove(uid)
        var people: [ID: User] = [:]
        for card in cards_ { people[card.creatorId] = card.host }
        if !wanted.isEmpty {
            let rows: [ProfileRow] = try await db.from("profiles").select(Self.profileColumns)
                .in("id", values: Array(wanted)).execute().value
            for row in rows { people[row.id] = row.user }
        }
        for block in blocks_ where people[block.blockedId] == nil {
            people[block.blockedId] = User(id: block.blockedId, firstName: block.blockedDisplayName ?? "Blocked user",
                                           bio: "", interests: [], alongFor: [])
        }

        var local = settings.load(for: uid)
        local.profileVisibility = me.visibility
        return AlongSnapshot(
            me: me.user, settings: local, users: Array(people.values), activities: activities, requests: requests,
            conversations: conversations_.map(\.conversation), messages: messages_.reversed().map(\.message),
            blockedUserIDs: Set(blocks_.map(\.blockedId)))
    }
}
