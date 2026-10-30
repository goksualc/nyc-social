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
    var interests: [String]?
    var lookingFor: [String]?
    var visibility: String?
    var ageConfirmedAt: Date?

    var user: User {
        User(id: id, firstName: displayName ?? "Someone", bio: bio ?? "",
             interests: (interests ?? []).compactMap(Interest.init(dbValue:)),
             alongFor: Set((lookingFor ?? []).compactMap(AlongPurpose.init(dbValue:))),
             avatarTone: tone(for: id), avatarPath: avatarUrl)
    }
}

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
    var workStyle: String?
    var startLng: Double?
    var startLat: Double?
    var endLng: Double?
    var endLat: Double?
    var viewerIsCreator: Bool
    var viewerIsParticipant: Bool

    /// Public, approximate view of the activity (what anyone may see).
    func activity() -> Activity {
        let area = publicArea ?? "Manhattan"
        let start = Coordinate(startLat ?? 0, startLng ?? 0)
        let details: ActivityDetails
        if type == "walk" {
            let end = Coordinate(endLat ?? start.latitude, endLng ?? start.longitude)
            details = .walk(WalkInfo(
                from: Place(name: startLabel ?? area, area: area, coordinate: start, isStreet: true),
                to: Place(name: endLabel ?? area, area: area, coordinate: end, isStreet: true),
                pace: Pace(rawValue: (pace ?? "casual").capitalized) ?? .casual))
        } else {
            details = .cowork(CoworkInfo(
                venue: Place(name: "", area: area, coordinate: start),
                style: WorkStyle(dbValue: workStyle ?? "") ?? .deepWork))
        }
        return Activity(
            id: id, title: title, hostID: creatorId, details: details, startDate: startTime, endDate: endTime,
            visibility: Visibility(rawValue: visibility.capitalized) ?? .public, capacity: maxParticipants,
            participantIDs: [], participantCount: participantCount, note: description,
            meetingDetails: "", hasPreciseAccess: false, isCancelled: status == "cancelled", createdAt: createdAt)
    }

    /// Minimal host identity from the card, for hosts whose full profile isn't readable.
    var host: User {
        User(id: creatorId, firstName: hostName, bio: "", interests: [], alongFor: [],
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
        switch activity.details {
        case .walk(var w):
            if let lat = startLat, let lng = startLng { w.from.coordinate = Coordinate(lat, lng) }
            if let lat = endLat, let lng = endLng { w.to.coordinate = Coordinate(lat, lng) }
            activity.details = .walk(w)
            activity.routeCoordinates = (routeCoordinates ?? []).compactMap { $0.count >= 2 ? Coordinate($0[1], $0[0]) : nil }
        case .cowork(var c):
            if let lat = startLat, let lng = startLng { c.venue.coordinate = Coordinate(lat, lng) }
            c.venue.name = cafeName ?? ""
            c.venue.address = address
            activity.details = .cowork(c)
        }
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

struct ConversationRow: Decodable {
    struct Member: Decodable { var userId: String }
    var id: String
    var activityId: String
    var createdAt: Date
    var conversationParticipants: [Member]

    var conversation: Conversation {
        Conversation(id: id, activityID: activityId, participantIDs: conversationParticipants.map(\.userId), createdAt: createdAt)
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
}

struct CreateCoworkParams: Encodable {
    var pTitle: String, pDescription: String, pStartTime: Date, pEndTime: Date
    var pMaxParticipants: Int, pVisibility: String, pWorkStyle: String
    // Not optional: Swift omits nil keys, and PostgREST matches functions by the exact set of argument names.
    // The server stores '' as NULL.
    var pCafeName: String, pAddress: String, pLng: Double, pLat: Double
    var pPlaceIdentifier: String
    var pMeetingDetails: String
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

struct ProfileUpdate: Encodable {
    var displayName: String, bio: String, interests: [String], lookingFor: [String], avatarUrl: String?
    var visibility: String?
    enum CodingKeys: String, CodingKey { case displayName, bio, interests, lookingFor, avatarUrl, visibility }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(bio, forKey: .bio)
        try c.encode(interests, forKey: .interests)
        try c.encode(lookingFor, forKey: .lookingFor)
        try c.encode(avatarUrl, forKey: .avatarUrl)            // explicit null clears the photo
        try c.encodeIfPresent(visibility, forKey: .visibility)
    }
}

struct MessageInsert: Encodable {
    var conversationId: String
    var content: String
}
