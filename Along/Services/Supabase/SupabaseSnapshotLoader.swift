import Foundation
import Supabase

/// Builds the signed-in user's `AlongSnapshot` from Supabase. Everything is fetched through RLS-protected tables
/// or the secure RPCs, so the result already contains only what this user may see.
struct SupabaseSnapshotLoader: Sendable {
    let manager: SupabaseManager
    let settings = LocalSettingsStore()

    static let profileColumns = "id, username, display_name, bio, avatar_url, visibility, hobbies, instagram_username, x_username, occupation, university, languages, favorite_neighborhoods, preferred_pace, preferred_duration, favorite_mode, discussion_topics, conversation_custom"
    /// Used when migration 7 hasn't been applied yet, so signing in still works.
    static let legacyProfileColumns = "id, username, display_name, bio, avatar_url, visibility"
    static let messageColumns = "id, conversation_id, sender_id, content, created_at"
    private var db: PostgrestClient { manager.client.schema("public") }

    func load() async throws -> AlongSnapshot {
        let uid = try manager.requireUserID()

        async let profile = SupabaseProfileService(manager: manager).loadMyProfile()
        async let cards: [ActivityCardRow] = db.rpc("list_my_activities").execute().value
        async let requestRows: [JoinRequestRow] = db.from("join_requests")
            .select("id, activity_id, requester_id, status, created_at")
            .order("created_at", ascending: false).limit(500).execute().value
        // Chats are read through RPCs that swap a hidden organizer's real id for an opaque alias; the tables themselves are
        // no longer readable by the app (migration 11).
        async let conversationRows: [ConversationRow] = db.rpc("list_my_conversations").execute().value
        async let messageRows: [MessageRow] = db.rpc("list_my_messages", params: ListMessagesParams(pConversation: nil, pBefore: nil, pLimit: 200)).execute().value
        async let blockRows: [BlockRow] = db.from("user_blocks").select("blocked_id, blocked_display_name").execute().value

        let (me, cards_, requests_, conversations_, messages_, blocks_) =
            try await (profile, cards, requestRows, conversationRows, messageRows, blockRows)

        // Retired cowork plans stay in the database but are not part of the app any more.
        let walkCards = cards_.filter { $0.type == "walk" }
        var activities = walkCards.map { $0.activity() }
        let known = Set(activities.map(\.id))
        let requests = requests_.map(\.request).filter { known.contains($0.activityID) }

        // Hosts see who is going; everyone else only gets the count from the server.
        for i in activities.indices {
            let mine = activities[i].hostID == uid
            if mine {
                activities[i].participantIDs = requests
                    .filter { $0.activityID == activities[i].id && $0.status == .accepted }.map(\.requesterID)
            }
        }

        // Exact places + meeting details, only for plans I host or have been accepted into.
        let preciseIDs = walkCards.filter { $0.viewerIsCreator || $0.viewerIsParticipant }.map(\.id)
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
        // A hidden organizer appears as an opaque alias ("anon:…"), which is not a profile id and must never be looked up.
        wanted = wanted.filter { UUID(uuidString: $0) != nil }
        var people: [ID: User] = [:]
        for card in walkCards { people[card.creatorId] = card.host }
        if !wanted.isEmpty {
            let rows: [ProfileRow]
            do {
                rows = try await db.from("profiles").select(Self.profileColumns).in("id", values: Array(wanted)).execute().value
            } catch {
                rows = try await db.from("profiles").select(Self.legacyProfileColumns).in("id", values: Array(wanted)).execute().value
            }
            for row in rows { people[row.id] = row.user }
        }
        // Ages exist only for people who chose to show them; failure just means no age is shown.
        let ages: [AgeRow] = (try? await db.rpc("profile_ages", params: ["p_ids": people.keys.filter { UUID(uuidString: $0) != nil }]).execute().value) ?? []
        for age in ages { people[age.id]?.age = age.age }
        for block in blocks_ where people[block.blockedId] == nil {
            people[block.blockedId] = User(id: block.blockedId, firstName: block.blockedDisplayName ?? "Blocked user",
                                           bio: "", hobbies: [])
        }

        var local = settings.load(for: uid)
        local.profileVisibility = me.visibility
        return AlongSnapshot(
            me: me.user, settings: local, users: Array(people.values), activities: activities, requests: requests,
            conversations: conversations_.map(\.conversation).filter { known.contains($0.activityID) }, messages: messages_.reversed().map(\.message),
            blockedUserIDs: Set(blocks_.map(\.blockedId)))
    }
}
