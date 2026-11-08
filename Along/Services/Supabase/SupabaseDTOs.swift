import Foundation

// Row types exactly as PostgREST returns them (snake_case → camelCase by the shared decoder),
// plus their mapping into the app's domain models.

private func tone(for id: String) -> Int { id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 6 } }

struct ProfileRow: Decodable {
    var id: String
    var username: String?
    var fullName: String?
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var visibility: String?
    var ageConfirmedAt: Date?
    var hobbies: [String]?
    var instagramUsername: String?
    var xUsername: String?
    var occupation: String?
    var university: String?
    var languages: [String]?
    var favoriteNeighborhoods: [String]?
    var preferredPace: String?
    var preferredDuration: Int?
    var discussionTopics: [String]?
    var conversationCustom: [String]?

    var user: User {
        User(id: id, firstName: displayName ?? "Someone", bio: bio ?? "", hobbies: hobbies ?? [],
             avatarTone: tone(for: id), avatarPath: avatarUrl,
             occupation: occupation, university: university, languages: languages ?? [],
             instagram: instagramUsername, xHandle: xUsername,
             pacePreference: preferredPace.flatMap(PacePreference.init(dbValue:)), preferredDuration: preferredDuration,
             favoriteNeighborhoods: favoriteNeighborhoods ?? [],
             discussionTopics: (discussionTopics ?? []).compactMap(ConversationTopic.init(dbValue:)),
             conversationCustom: conversationCustom ?? [])
    }
}

struct AgeRow: Decodable { var id: String; var age: Int }

struct ActivityCardRow: Decodable {
    var id: String
    var creatorId: String
    var type: String
    var title: String
    var description: String
    var startTime: Date
    var endTime: Date
    var maxParticipants: Int
    var visibility: String
    var status: String
    var createdAt: Date
    var participantCount: Int
    var hostName: String
    var hostAvatarPath: String?
    var publicArea: String?
    var startLabel: String?
    var endLabel: String?
    var pace: String?
    var startLng: Double?
    var startLat: Double?
    var endLng: Double?
    var endLat: Double?
    var viewerIsCreator: Bool
    var viewerIsParticipant: Bool
    var hostAnonymous: Bool?
    var hostInterests: [String]?
    var mindPrompt: String?

    /// Public, approximate view of the activity (what anyone may see).
    func activity() -> Activity {
        let area = publicArea ?? "New York City"
        let start = Coordinate(startLat ?? 0, startLng ?? 0)
        let end = Coordinate(endLat ?? start.latitude, endLng ?? start.longitude)
        let walk = WalkInfo(
            from: Place(name: startLabel ?? area, area: area, coordinate: start, isStreet: true),
            to: Place(name: endLabel ?? area, area: area, coordinate: end, isStreet: true),
            pace: Pace(rawValue: (pace ?? "casual").capitalized) ?? .casual)
        return Activity(
            id: id, title: title, hostID: creatorId, walk: walk, startDate: startTime, endDate: endTime,
            visibility: Visibility(rawValue: visibility.capitalized) ?? .public, capacity: maxParticipants,
            participantIDs: [], participantCount: participantCount, note: description,
            meetingDetails: "", hasPreciseAccess: false, isCancelled: status == "cancelled", createdAt: createdAt,
            hostAnonymous: hostAnonymous ?? false, hostInterests: hostInterests ?? [],
            mindPrompt: mindPrompt.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Minimal host identity from the card, for hosts whose full profile isn't readable.
    var host: User {
        // A hidden organizer arrives as an opaque alias with no name or photo; keep it that way.
        if (hostAnonymous ?? false) && User.isAlias(creatorId) { return .anonymousHost(id: creatorId, interests: hostInterests ?? []) }
        return User(id: creatorId, firstName: hostName, bio: "", hobbies: [],
             avatarTone: tone(for: creatorId), avatarPath: hostAvatarPath)
    }
}

struct PrivateDetailsRow: Decodable {
    var activityId: String
    var type: String
    var startLng: Double?
    var startLat: Double?
    var endLng: Double?
    var endLat: Double?
    var routeCoordinates: [[Double]]?
    var cafeName: String?
    var address: String?
    var meetingDetails: String?

    /// Upgrades a public activity with exact places and meeting instructions.
    func apply(to activity: inout Activity) {
        activity.hasPreciseAccess = true
        activity.meetingDetails = meetingDetails ?? ""
        if let lat = startLat, let lng = startLng { activity.walk.from.coordinate = Coordinate(lat, lng) }
        if let lat = endLat, let lng = endLng { activity.walk.to.coordinate = Coordinate(lat, lng) }
        activity.routeCoordinates = (routeCoordinates ?? []).compactMap { $0.count >= 2 ? Coordinate($0[1], $0[0]) : nil }
    }
}

struct JoinRequestRow: Decodable {
    var id: String
    var activityId: String
    var requesterId: String
    var status: String
    var createdAt: Date

    var request: JoinRequest {
        let s: RequestStatus
        switch status {
        case "accepted": s = .accepted
        case "declined": s = .declined
        case "cancelled": s = .withdrawn
        default: s = .pending
        }
        return JoinRequest(id: id, activityID: activityId, requesterID: requesterId, status: s, createdAt: createdAt)
    }
}

struct ListMessagesParams: Encodable {
    var pConversation: String?
    var pBefore: Date?
    var pLimit: Int
}

struct SendMessageParams: Encodable { var pConversation: String, pContent: String }

struct ConversationRow: Decodable {
    struct Member: Decodable { var userId: String }
    var id: String
    var activityId: String
    var createdAt: Date
    var requestId: String?
    var conversationParticipants: [Member]

    var conversation: Conversation {
        Conversation(id: id, activityID: activityId, requestID: requestId, participantIDs: conversationParticipants.map(\.userId), createdAt: createdAt)
    }
}

struct MessageRow: Decodable {
    var id: String
    var conversationId: String
    var senderId: String
    var content: String
    var createdAt: Date

    var message: Message {
        Message(id: id, conversationID: conversationId, senderID: senderId, text: content, sentAt: createdAt)
    }
}

struct BlockRow: Decodable {
    var blockedId: String
    var blockedDisplayName: String?
}

// MARK: - RPC / update payloads (camelCase here ⇒ snake_case on the wire, e.g. `pMaxParticipants` → `p_max_participants`)

struct CreateWalkParams: Encodable {
    var pTitle: String, pDescription: String, pStartTime: Date, pEndTime: Date
    var pMaxParticipants: Int, pVisibility: String, pPace: String
    var pStartLabel: String, pEndLabel: String
    var pStartLng: Double, pStartLat: Double, pEndLng: Double, pEndLat: Double
    var pRoute: [[Double]]?
    var pMeetingDetails: String
    // Not optional: PostgREST matches by the exact argument set. The server stores '' as no value.
    var pAnonymousHost: Bool, pHostInterests: [String], pMindPrompt: String
}

struct UpdateActivityParams: Encodable {
    var pActivityId: String
    var pStartTime: Date?, pEndTime: Date?
    var pMaxParticipants: Int?
    var pDescription: String?, pMeetingDetails: String?
}

struct DiscoverParams: Encodable {
    var pMinLng: Double, pMinLat: Double, pMaxLng: Double, pMaxLat: Double
    var pType: String?, pFrom: Date?, pTo: Date?
    var pLimit: Int, pOffset: Int
}

struct NearbyParams: Encodable {
    var pLng: Double, pLat: Double, pRadiusM: Double
    var pType: String?, pLimit: Int
}

struct CompleteProfileParams: Encodable {
    var pDisplayName: String, pBio: String, pInterests: [String], pLookingFor: [String], pConfirmAge: Bool
}

struct RouteSearchParams: Encodable {
    var pRoute: [[Double]], pCorridorM: Double
    var pFrom: Date?, pTo: Date?, pWhen: Date?
    var pLimit: Int
}

struct RouteMatchRow: Decodable {
    var card: ActivityCardRow
    var overlapPct: Double, routeDistanceM: Double, directionDiffDeg: Double
    var startsNear: Bool, endsNear: Bool, score: Double

    func match() -> RouteMatch {
        RouteMatch(activity: card.activity(), host: card.host, overlap: overlapPct, routeDistanceMeters: routeDistanceM,
                   directionDiffDegrees: directionDiffDeg, startsNear: startsNear, endsNear: endsNear, score: score)
    }
}

struct ProfileUpdate: Encodable {
    var displayName: String, bio: String, hobbies: [String]
    var instagramUsername: String?, xUsername: String?, occupation: String?, university: String?
    var languages: [String]
    var favoriteNeighborhoods: [String], preferredPace: String?, preferredDuration: Int?
    var discussionTopics: [String], conversationCustom: [String]
    var visibility: String?
    enum CodingKeys: String, CodingKey {
        case displayName, bio, hobbies, instagramUsername, xUsername, occupation, university, languages
        case favoriteNeighborhoods, preferredPace, preferredDuration, discussionTopics, conversationCustom
        case visibility
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(bio, forKey: .bio)
        try c.encode(hobbies, forKey: .hobbies)
        // Explicit nulls clear an optional field.
        try c.encode(instagramUsername, forKey: .instagramUsername)
        try c.encode(xUsername, forKey: .xUsername)
        try c.encode(occupation, forKey: .occupation)
        try c.encode(university, forKey: .university)
        try c.encode(languages, forKey: .languages)
        try c.encode(favoriteNeighborhoods, forKey: .favoriteNeighborhoods)
        try c.encode(preferredPace, forKey: .preferredPace)
        try c.encode(preferredDuration, forKey: .preferredDuration)
        try c.encode(discussionTopics, forKey: .discussionTopics)
        try c.encode(conversationCustom, forKey: .conversationCustom)
        try c.encodeIfPresent(visibility, forKey: .visibility)
    }
}

/// The photo only. Kept separate so changing it can never rewrite (or fail because of) any other profile field,
/// and saving the profile form can never put an old photo back.
struct AvatarUpdate: Encodable {
    var avatarUrl: String?
    enum CodingKeys: String, CodingKey { case avatarUrl }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(avatarUrl, forKey: .avatarUrl)          // explicit null clears the photo
    }
}

enum AvatarStoragePath {
    /// `<lowercase user id>/avatar-<unix ms>.jpg`
    static func make(userID: String, now: Date = .now) -> String {
        "\(userID.lowercased())/avatar-\(Int64(now.timeIntervalSince1970 * 1000)).jpg"
    }
}

/// First-run extras written once, at the end of onboarding.
struct OnboardingUpdate: Encodable {
    var instagramUsername: String?, xUsername: String?
    var hobbies: [String]
    var preferredPace: String?, preferredDuration: Int?, favoriteNeighborhoods: [String]
    var birthday: String?
    enum CodingKeys: String, CodingKey {
        case instagramUsername, xUsername, hobbies, preferredPace, preferredDuration, favoriteNeighborhoods, birthday
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instagramUsername, forKey: .instagramUsername)
        try c.encode(xUsername, forKey: .xUsername)
        try c.encode(hobbies, forKey: .hobbies)
        try c.encode(preferredPace, forKey: .preferredPace)
        try c.encode(preferredDuration, forKey: .preferredDuration)
        try c.encode(favoriteNeighborhoods, forKey: .favoriteNeighborhoods)
        try c.encodeIfPresent(birthday, forKey: .birthday)
    }
}

struct MessageInsert: Encodable {
    var conversationId: String
    var content: String
}
