import XCTest
import MapKit
@testable import Along

// MARK: - Configuration safety

final class SupabaseConfigTests: XCTestCase {
    func testMissingOrPlaceholderValuesAreReportedAsMissing() {
        XCTAssertEqual(SupabaseConfig.validate(url: nil, key: nil), .failure(.missing))
        XCTAssertEqual(SupabaseConfig.validate(url: "", key: "x"), .failure(.missing))
        XCTAssertEqual(SupabaseConfig.validate(url: "$(SUPABASE_URL)", key: "$(SUPABASE_PUBLISHABLE_KEY)"), .failure(.missing))
        XCTAssertEqual(SupabaseConfig.validate(url: "https://YOUR-PROJECT-REF.supabase.co", key: "sb_publishable_abc"), .failure(.missing))
    }

    func testRejectsInsecureAndMalformedURLs() {
        XCTAssertEqual(SupabaseConfig.validate(url: "http://abc.supabase.co", key: "sb_publishable_abc"), .failure(.invalidURL))
        XCTAssertEqual(SupabaseConfig.validate(url: "not a url", key: "sb_publishable_abc"), .failure(.invalidURL))
        XCTAssertNoThrow(try SupabaseConfig.validate(url: "http://127.0.0.1:54321", key: "sb_publishable_abc").get(), "local dev may use http")
    }

    func testRefusesSecretAndServiceRoleKeys() {
        XCTAssertEqual(SupabaseConfig.validate(url: "https://abc.supabase.co", key: "sb_secret_abc123").mapError { $0 }, .failure(.secretKeyDetected))
        func jwt(role: String) -> String {
            func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") }
            return "\(b64("{\"alg\":\"HS256\"}")).\(b64("{\"role\":\"\(role)\"}")).sig"
        }
        XCTAssertEqual(SupabaseConfig.validate(url: "https://abc.supabase.co", key: jwt(role: "service_role")), .failure(.secretKeyDetected))
        XCTAssertNoThrow(try SupabaseConfig.validate(url: "https://abc.supabase.co", key: jwt(role: "anon")).get())
        XCTAssertNoThrow(try SupabaseConfig.validate(url: "https://abc.supabase.co", key: "sb_publishable_abc").get())
    }

    @MainActor func testAppRunsInDemoModeWithoutConfiguration() {
        // The test host is built without Secrets.xcconfig, so the app must fall back rather than crash.
        if case .failure = SupabaseConfig.load() { XCTAssertFalse(AppSession.make().isLive) }
    }
}

// MARK: - Error presentation

final class ErrorPresenterTests: XCTestCase {
    func testServerCodesBecomeFriendlyMessages() {
        XCTAssertEqual(AlongError(serverCode: "activity_full"), .activityFull)
        XCTAssertEqual(AlongError(serverCode: "outside_manhattan"), .outsideManhattan)
        XCTAssertEqual(AlongError(serverCode: "already_requested"), .alreadyRequested)
        XCTAssertNil(AlongError(serverCode: "duplicate key value violates unique constraint \"x\""), "raw database text never maps")
        XCTAssertEqual(AlongError.activityFull.errorDescription, "This plan is already full.")
    }

    func testTransportErrors() {
        XCTAssertEqual(ErrorPresenter.map(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(ErrorPresenter.map(URLError(.timedOut)), .offline)
        XCTAssertEqual(ErrorPresenter.map(CancellationError()), .cancelled)
    }

    func testUnknownErrorsUseTheCallersContextualMessageNotRawText() {
        struct Raw: Error, LocalizedError { var errorDescription: String? { "PGRST116: JSON object requested, multiple (or no) rows returned" } }
        XCTAssertEqual(ErrorPresenter.message(for: Raw(), fallback: "Couldn't publish your walk. Try again."),
                       "Couldn't publish your walk. Try again.")
        XCTAssertEqual(ErrorPresenter.message(for: AlongError.activityFull, fallback: "x"), "This plan is already full.")
    }
}

// MARK: - Wire format (what the SQL functions expect)

final class WireFormatTests: XCTestCase {
    private func keys(_ value: some Encodable) throws -> Set<String> {
        let data = try SupabaseCoding.makeEncoder().encode(value)
        return Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys)
    }

    func testRPCParameterNamesMatchTheSQLSignatures() throws {
        let t = Date()
        XCTAssertEqual(try keys(CreateWalkParams(pTitle: "", pDescription: "", pStartTime: t, pEndTime: t, pMaxParticipants: 1, pVisibility: "public",
                                                 pPace: "casual", pStartLabel: "", pEndLabel: "", pStartLng: 0, pStartLat: 0, pEndLng: 0, pEndLat: 0,
                                                 pRoute: [[0, 0]], pMeetingDetails: "")),
                       ["p_title", "p_description", "p_start_time", "p_end_time", "p_max_participants", "p_visibility", "p_pace",
                        "p_start_label", "p_end_label", "p_start_lng", "p_start_lat", "p_end_lng", "p_end_lat", "p_route", "p_meeting_details"])
        XCTAssertEqual(try keys(CreateCoworkParams(pTitle: "", pDescription: "", pStartTime: t, pEndTime: t, pMaxParticipants: 1, pVisibility: "public",
                                                   pWorkStyle: "social", pCafeName: "", pAddress: "a", pLng: 0, pLat: 0, pPlaceIdentifier: "p", pMeetingDetails: "")),
                       ["p_title", "p_description", "p_start_time", "p_end_time", "p_max_participants", "p_visibility", "p_work_style",
                        "p_cafe_name", "p_address", "p_lng", "p_lat", "p_place_identifier", "p_meeting_details"])
        XCTAssertEqual(try keys(DiscoverParams(pMinLng: 0, pMinLat: 0, pMaxLng: 1, pMaxLat: 1, pType: "walk", pFrom: t, pTo: t, pLimit: 1, pOffset: 0)),
                       ["p_min_lng", "p_min_lat", "p_max_lng", "p_max_lat", "p_type", "p_from", "p_to", "p_limit", "p_offset"])
        XCTAssertEqual(try keys(NearbyParams(pLng: 0, pLat: 0, pRadiusM: 1, pType: "walk", pLimit: 1)), ["p_lng", "p_lat", "p_radius_m", "p_type", "p_limit"])
        XCTAssertEqual(try keys(UpdateActivityParams(pActivityId: "x", pStartTime: t, pEndTime: t, pMaxParticipants: 2, pDescription: "d", pMeetingDetails: "m")),
                       ["p_activity_id", "p_start_time", "p_end_time", "p_max_participants", "p_description", "p_meeting_details"])
        XCTAssertEqual(try keys(CompleteProfileParams(pDisplayName: "a", pBio: "", pInterests: [], pLookingFor: [], pConfirmAge: true)),
                       ["p_display_name", "p_bio", "p_interests", "p_looking_for", "p_confirm_age"])
        XCTAssertEqual(try keys(MessageInsert(conversationId: "c", content: "hi")), ["conversation_id", "content"])
    }

    func testClearingAvatarSendsExplicitNull() throws {
        let data = try SupabaseCoding.makeEncoder().encode(ProfileUpdate(displayName: "A", bio: "", interests: [], lookingFor: [], avatarUrl: nil, visibility: nil))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(json["avatar_url"] is NSNull)
        XCTAssertNil(json["visibility"])
    }

    func testPostgresTimestampsWithMicrosecondsDecode() throws {
        let d = SupabaseCoding.makeDecoder()
        struct Box: Decodable { var createdAt: Date }
        for raw in ["2026-10-28T15:04:05.123456+00:00", "2026-10-28T15:04:05+00:00", "2026-10-28T15:04:05.1Z"] {
            let box = try d.decode(Box.self, from: Data("{\"created_at\":\"\(raw)\"}".utf8))
            XCTAssertEqual(box.createdAt.timeIntervalSince1970, 1_793_199_845, accuracy: 1)
        }
    }

    func testActivityCardMapsToPublicApproximateActivity() throws {
        let json = """
        {"id":"a1","creator_id":"h1","type":"walk","title":"Evening walk","description":"hi","start_time":"2026-10-28T21:00:00.5+00:00",
         "end_time":"2026-10-28T22:00:00+00:00","max_participants":2,"visibility":"public","status":"active","created_at":"2026-10-28T10:00:00+00:00",
         "updated_at":"2026-10-28T10:00:00+00:00","participant_count":1,"host_name":"Göksu","host_avatar_path":null,"public_area":"Upper West Side",
         "start_label":"72nd St","end_label":"55th St","pace":"casual","work_style":null,"start_lng":-73.968,"start_lat":40.7725,
         "end_lng":-73.9755,"end_lat":40.762,"viewer_is_creator":false,"viewer_is_participant":false}
        """
        let row = try SupabaseCoding.makeDecoder().decode(ActivityCardRow.self, from: Data(json.utf8))
        let a = row.activity()
        XCTAssertEqual(a.kind, .walk)
        XCTAssertEqual(a.spotsLeft, 1)
        XCTAssertEqual(a.publicLocationLabel, "72nd St → 55th St")
        XCTAssertFalse(a.hasPreciseAccess)
        XCTAssertEqual(a.meetingDetails, "")
        XCTAssertEqual(row.host.firstName, "Göksu")
    }

    func testCoworkCardNeverCarriesAVenueName() throws {
        let json = """
        {"id":"c1","creator_id":"h1","type":"cowork","title":"Working from SoHo","description":"","start_time":"2026-10-29T17:00:00+00:00",
         "end_time":"2026-10-29T21:00:00+00:00","max_participants":2,"visibility":"public","status":"active","created_at":"2026-10-28T10:00:00+00:00",
         "updated_at":"2026-10-28T10:00:00+00:00","participant_count":0,"host_name":"Alex","host_avatar_path":null,"public_area":"SoHo",
         "start_label":null,"end_label":null,"pace":null,"work_style":"deep_work","start_lng":-74.003,"start_lat":40.7225,
         "end_lng":null,"end_lat":null,"viewer_is_creator":false,"viewer_is_participant":false}
        """
        let a = try SupabaseCoding.makeDecoder().decode(ActivityCardRow.self, from: Data(json.utf8)).activity()
        XCTAssertEqual(a.cowork?.venue.name, "")
        XCTAssertEqual(a.publicLocationLabel, "SoHo · Coffee shop")
        XCTAssertEqual(a.cowork?.style, .deepWork)
    }

    func testPrivateDetailsUpgradeAnActivity() throws {
        let card = """
        {"id":"c1","creator_id":"h1","type":"cowork","title":"t","description":"","start_time":"2026-10-29T17:00:00+00:00","end_time":"2026-10-29T21:00:00+00:00",
         "max_participants":2,"visibility":"public","status":"active","created_at":"2026-10-28T10:00:00+00:00","updated_at":"2026-10-28T10:00:00+00:00",
         "participant_count":1,"host_name":"Alex","host_avatar_path":null,"public_area":"SoHo","start_label":null,"end_label":null,"pace":null,
         "work_style":"social","start_lng":-74.003,"start_lat":40.7225,"end_lng":null,"end_lat":null,"viewer_is_creator":false,"viewer_is_participant":true}
        """
        let details = """
        {"activity_id":"c1","type":"cowork","start_lng":-74.0003,"start_lat":40.7233,"end_lng":null,"end_lat":null,"route_coordinates":null,
         "cafe_name":"Lantern Coffee","address":"142 Prince St","meeting_details":"Big table by the window"}
        """
        let d = SupabaseCoding.makeDecoder()
        var a = try d.decode(ActivityCardRow.self, from: Data(card.utf8)).activity()
        try d.decode(PrivateDetailsRow.self, from: Data(details.utf8)).apply(to: &a)
        XCTAssertTrue(a.hasPreciseAccess)
        XCTAssertEqual(a.cowork?.venue.name, "Lantern Coffee")
        XCTAssertEqual(a.cowork?.venue.address, "142 Prince St")
        XCTAssertEqual(a.cowork?.venue.coordinate.latitude ?? 0, 40.7233, accuracy: 1e-6)
        XCTAssertEqual(a.meetingDetails, "Big table by the window")
    }

    func testRequestStatusMapping() throws {
        let d = SupabaseCoding.makeDecoder()
        func status(_ s: String) throws -> RequestStatus {
            try d.decode(JoinRequestRow.self, from: Data("{\"id\":\"r\",\"activity_id\":\"a\",\"requester_id\":\"u\",\"status\":\"\(s)\",\"created_at\":\"2026-10-28T10:00:00+00:00\"}".utf8)).request.status
        }
        XCTAssertEqual(try status("cancelled"), .withdrawn)
        XCTAssertEqual(try status("accepted"), .accepted)
        XCTAssertEqual(try status("declined"), .declined)
        XCTAssertEqual(try status("pending"), .pending)
    }

    @MainActor func testRouteDownsamplingKeepsEndpoints() {
        let coords = (0..<2500).map { Coordinate(40 + Double($0) * 1e-5, -73.9) }
        let out = CreateActivityViewModel.downsample(coords, to: 400)
        XCTAssertEqual(out.count, 400)
        XCTAssertEqual(out.first, coords.first)
        XCTAssertEqual(out.last, coords.last)
    }
}

// MARK: - Discovery & store behaviour (mock backend, same contract as the RPC)

@MainActor
final class DiscoveryTests: XCTestCase {
    private func store() async throws -> AppStore { try await AppStore.bootstrap(backend: MockAlongBackend()) }

    func testBoundingBoxQueryOnlyReturnsPlansInsideTheBox() async throws {
        let store = try await store()
        let manhattan = ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: .now)
        await store.discover(manhattan)
        let all = store.discoverable.count
        XCTAssertGreaterThanOrEqual(all, 8)

        var tiny = manhattan   // a few blocks around SoHo
        tiny.minLat = 40.718; tiny.maxLat = 40.728; tiny.minLng = -74.010; tiny.maxLng = -73.995
        await store.discover(tiny)
        XCTAssertEqual(store.discoverable.map(\.title), ["Working from SoHo"])
    }

    func testKindAndTimeWindowFilters() async throws {
        let store = try await store()
        var q = ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .walks, now: .now)
        await store.discover(q)
        XCTAssertTrue(store.discoverable.allSatisfy { $0.kind == .walk })

        q = ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .tomorrow, now: .now)
        await store.discover(q)
        XCTAssertFalse(store.discoverable.isEmpty)
        XCTAssertTrue(store.discoverable.allSatisfy { ActivityTime.isTomorrow($0.startDate) })
    }

    func testPaginationAddsPagesWithoutDuplicates() async throws {
        let store = try await store()
        var q = ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: .now)
        q.limit = 4
        await store.discover(q)
        XCTAssertEqual(store.discovered.count, 4)
        XCTAssertTrue(store.hasMoreDiscovery)
        await store.loadMoreDiscovery()
        XCTAssertEqual(store.discovered.count, 8)
        XCTAssertEqual(Set(store.discovered.map(\.id)).count, 8)
    }

    func testBlockingRemovesTheHostFromDiscovery() async throws {
        let store = try await store()
        await store.discover(ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: .now))
        XCTAssertTrue(store.discoverable.contains { $0.hostID == "alex" })
        await store.block("alex")
        XCTAssertFalse(store.discoverable.contains { $0.hostID == "alex" })
    }

    func testRequestFlowUpdatesStoreAndRollsBackFailedMessages() async throws {
        let store = try await store()
        await store.discover(ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: .now))
        let plan = try XCTUnwrap(store.activity("act-chelsea"))
        await store.updateSettings { $0.demoHostsRespond = false }
        await store.requestToJoin(plan)
        XCTAssertEqual(store.role(in: plan), .pending)
        await store.withdrawRequest(plan)
        XCTAssertNil(store.role(in: plan))

        // Optimistic send into a conversation that closes → rolled back, nothing left behind.
        let convo = try XCTUnwrap(store.conversation(id: "conv-jonas"))
        let ok = await store.send("hello", in: convo)
        XCTAssertTrue(ok)
        let after = try XCTUnwrap(store.activity("act-park"))
        await store.leave(after)
        let before = store.messages(in: convo).count
        let failed = await store.send("still there?", in: convo)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.messages(in: convo).count, before, "optimistic bubble was rolled back")
    }

    func testDiscoveryWindowsAreOverlapBased() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15))!
        let today = ExploreViewModel.window(for: .today, now: now)
        XCTAssertEqual(today.from, now)
        XCTAssertEqual(today.to, cal.date(from: DateComponents(year: 2026, month: 10, day: 29)))
        let tomorrow = ExploreViewModel.window(for: .tomorrow, now: now)
        XCTAssertEqual(tomorrow.from, cal.date(from: DateComponents(year: 2026, month: 10, day: 29)))
    }
}
