import XCTest
@testable import Along

final class BackendRulesTests: XCTestCase {
    private func backend() -> MockAlongBackend { MockAlongBackend() }

    func testSeedHasLiveActivitiesAndNoExpiredOnes() async throws {
        let snap = try await backend().loadSnapshot()
        let live = snap.activities.filter { $0.isActive(at: .now) }
        XCTAssertGreaterThanOrEqual(live.count, 8)
        XCTAssertTrue(snap.activities.contains { $0.isExpired(at: .now) }, "past plans exist for the Past tab")
    }

    func testPublicActivitiesAreRedactedForNonMembers() async throws {
        let snap = try await backend().loadSnapshot()
        let chelsea = snap.activities.first { $0.id == "act-chelsea" }!
        XCTAssertFalse(chelsea.hasPreciseAccess)
        XCTAssertEqual(chelsea.meetingDetails, "")
        let exact = SeedData.make(now: .now).activities.first { $0.id == "act-chelsea" }!.walk.from.coordinate
        XCTAssertNotEqual(chelsea.walk.from.coordinate, exact, "exact start is withheld")
        let mine = snap.activities.first { $0.id == "act-midtown" }!
        XCTAssertTrue(mine.hasPreciseAccess)
        XCTAssertFalse(mine.meetingDetails.isEmpty)
    }

    func testRequestThenWithdraw() async throws {
        let b = backend()
        var snap = try await b.requestToJoin(activityID: "act-chelsea")
        XCTAssertEqual(snap.requests.first { $0.activityID == "act-chelsea" && $0.requesterID == "me" }?.status, .pending)
        do { _ = try await b.requestToJoin(activityID: "act-chelsea"); XCTFail("duplicate request allowed") } catch {}
        snap = try await b.withdrawRequest(activityID: "act-chelsea")
        XCTAssertEqual(snap.requests.first { $0.activityID == "act-chelsea" }?.status, .withdrawn)
    }

    func testCannotJoinOwnPlan() async {
        do { _ = try await backend().requestToJoin(activityID: "act-midtown"); XCTFail() } catch {}
    }

    func testAcceptUpdatesSpotsAndCreatesConversation_thenFullBlocksNext() async throws {
        let b = backend()
        var snap = try await b.respond(requestID: "req-emma", accept: true)
        let a = snap.activities.first { $0.id == "act-midtown" }!
        XCTAssertEqual(a.spotsLeft, 0)
        XCTAssertTrue(a.participantIDs.contains("emma"))
        XCTAssertTrue(snap.conversations.contains { $0.activityID == "act-midtown" && $0.participantIDs.contains("emma") })
        do { _ = try await b.respond(requestID: "req-daniel", accept: true); XCTFail("accepted into a full plan") } catch AlongError.activityFull {}
        snap = try await b.respond(requestID: "req-daniel", accept: false)
        XCTAssertEqual(snap.requests.first { $0.id == "req-daniel" }?.status, .declined)
    }

    func testMessagingRequiresAcceptedRequest() async throws {
        let b = backend()
        let sent = try await b.sendMessage(conversationID: "conv-priya", text: "  hello  ")
        XCTAssertEqual(sent.text, "hello")
        let snap = try await b.leave(activityID: "act-park")
        do { _ = try await b.sendMessage(conversationID: "conv-jonas", text: "hi"); XCTFail("chat stayed open after leaving") }
        catch AlongError.chatClosed {}
        XCTAssertEqual(snap.activities.first { $0.id == "act-park" }?.participantIDs.contains("me"), false)
    }

    func testBlockingHidesPlansRequestsAndChats() async throws {
        let snap = try await backend().block(userID: "maya")
        XCTAssertFalse(snap.activities.contains { $0.hostID == "maya" })
        let careers = try await backend().block(userID: "emma")
        XCTAssertFalse(careers.requests.contains { $0.activityID == "act-careers" })
        let snap2 = try await backend().block(userID: "emma")
        XCTAssertFalse(snap2.requests.contains { $0.requesterID == "emma" })
        let snap3 = try await backend().block(userID: "priya")
        XCTAssertFalse(snap3.conversations.contains { $0.participantIDs.contains("priya") })
    }

    func testCreateValidatesCityAndTimes() async throws {
        let b = backend()
        let manhattan = NYCGeo.street(40)
        let jerseyCity = Place(name: "Liberty State Park", area: "", coordinate: .init(40.7108, -74.0536))
        func draft(_ w: WalkInfo, start: Date = .now.addingTimeInterval(3600)) -> ActivityDraft {
            ActivityDraft(title: "t", walk: w, startDate: start, endDate: start.addingTimeInterval(3600),
                          visibility: .public, capacity: 2, note: "", meetingDetails: "")
        }
        do { _ = try await b.createActivity(draft(.init(from: jerseyCity, to: manhattan, pace: .casual))); XCTFail() } catch AlongError.outsideNYC {}
        do { _ = try await b.createActivity(draft(.init(from: manhattan, to: NYCGeo.street(60), pace: .casual), start: .now.addingTimeInterval(-7200))); XCTFail() } catch AlongError.startInPast {}
        // Any two places in the five boroughs work, including across the East River.
        let park = Place(name: "Prospect Park", area: "Prospect Park", coordinate: .init(40.6602, -73.9690))
        let zoo = Place(name: "Bronx Zoo", area: "Bronx Zoo", coordinate: .init(40.8506, -73.8770))
        let ferry = Place(name: "St. George", area: "St. George", coordinate: .init(40.6437, -74.0735))
        for (a, c) in [(park, manhattan), (manhattan, zoo), (ferry, park)] { _ = try await b.createActivity(draft(.init(from: a, to: c, pace: .casual))) }
        let snap = try await b.createActivity(draft(.init(from: NYCGeo.street(40), to: NYCGeo.street(60), pace: .fast)))
        XCTAssertEqual(snap.activities.count, SeedData.make(now: .now).activities.count + 4)
        // The optional "What's on your mind?" prompt is kept, trimmed.
        var withPrompt = draft(.init(from: NYCGeo.street(40), to: NYCGeo.street(60), pace: .fast))
        withPrompt.mindPrompt = "  Life, work, random thoughts  "
        let snap2 = try await b.createActivity(withPrompt)
        XCTAssertEqual(snap2.activities.filter { $0.mindPrompt == "Life, work, random thoughts" }.count, 1)
    }

    func testPrivatePlansAreCreatedButNeverDiscoverable() async throws {
        let b = backend()
        let d = ActivityDraft(title: "Private", walk: .init(from: NYCGeo.street(40), to: NYCGeo.street(60), pace: .casual),
                              startDate: .now.addingTimeInterval(3600), endDate: .now.addingTimeInterval(7200),
                              visibility: .private, capacity: 1, note: "", meetingDetails: "")
        let snap = try await b.createActivity(d)
        let store = await MainActor.run { AppStore(backend: b, snapshot: snap) }
        let (inPlans, onMap) = await MainActor.run {
            (store.plans(upcoming: true).contains { $0.activity.title == "Private" }, store.discoverable.contains { $0.title == "Private" })
        }
        XCTAssertTrue(inPlans)
        XCTAssertFalse(onMap)
    }

    func testCancelClosesPendingRequests() async throws {
        let snap = try await backend().cancelActivity(id: "act-midtown")
        XCTAssertTrue(snap.activities.first { $0.id == "act-midtown" }!.isCancelled)
        XCTAssertTrue(snap.requests.filter { $0.activityID == "act-midtown" }.allSatisfy { $0.status != .pending })
    }

    func testDemoHostAcceptsPendingRequest() async {
        let snap = await backend().simulateHostResponse(activityID: "act-careers")
        XCTAssertEqual(snap.requests.first { $0.id == "req-me-careers" }?.status, .accepted)
        XCTAssertTrue(snap.activities.first { $0.id == "act-careers" }!.hasPreciseAccess)
    }
}

final class GeoAndTimeTests: XCTestCase {
    func testCityBoundary() {
        XCTAssertTrue(NYCGeo.contains(.init(40.7580, -73.9855)))   // Times Square
        XCTAssertTrue(NYCGeo.contains(.init(40.7794, -73.9632)))   // The Met
        XCTAssertTrue(NYCGeo.contains(.init(40.7358, -74.0036)))   // West Village
        for (name, c) in [("Brooklyn", Coordinate(40.6782, -73.9442)), ("Queens", Coordinate(40.7282, -73.7949)), ("Coney Island", Coordinate(40.5755, -73.9707)),
                          ("The Bronx", Coordinate(40.8296, -73.9262)), ("Staten Island", Coordinate(40.5795, -74.1502)), ("Rockaway", Coordinate(40.5834, -73.8160))] {
            XCTAssertTrue(NYCGeo.contains(c), name)
        }
        XCTAssertEqual(NYCGeo.borough(of: .init(40.7580, -73.9855)), "Manhattan")
        XCTAssertEqual(NYCGeo.borough(of: .init(40.5795, -74.1502)), "Staten Island")
        XCTAssertFalse(NYCGeo.contains(.init(40.7178, -74.0431)))  // Jersey City
        XCTAssertFalse(NYCGeo.contains(.init(40.7357, -74.1724)))  // Newark
        XCTAssertFalse(NYCGeo.contains(.init(40.9312, -73.8987)))  // Yonkers
        XCTAssertFalse(NYCGeo.contains(.init(40.7062, -73.6187)))  // Hempstead
        XCTAssertFalse(NYCGeo.contains(.init(40.3000, -73.9000)))  // open ocean
        for p in SeedData.make(now: .now).activities { XCTAssertTrue(NYCGeo.contains(Coordinate(p.mapCoordinate)), p.title) }
    }

    func testApproximateCoordinateIsCoarse() {
        let c = Coordinate(40.77371, -73.96634)
        XCTAssertGreaterThan(c.distance(to: c.approximate), 0)
        XCTAssertLessThan(c.distance(to: c.approximate), 400)
    }

    func testStreetsAndOrdinals() {
        XCTAssertEqual(NYCGeo.ordinal(72), "72nd"); XCTAssertEqual(NYCGeo.ordinal(11), "11th")
        XCTAssertEqual(NYCGeo.street(55).name, "55th St")
        XCTAssertEqual(NYCGeo.suggestions(matching: "72").first?.name, "72nd St")
    }

    func testTimeFormatting() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        ActivityTime.calendar = cal
        defer { ActivityTime.calendar = .current }
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 10))!
        let tomorrow1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 13))!
        let tomorrow5 = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 17))!
        XCTAssertEqual(ActivityTime.day(tomorrow1, now: now), "Tomorrow")
        XCTAssertTrue(ActivityTime.range(tomorrow1, tomorrow5).contains("1–5"))
        let am = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 11))!
        let pm = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 15))!
        XCTAssertEqual(ActivityTime.day(am, now: now), "Fri")
        XCTAssertTrue(ActivityTime.range(am, pm).contains("11"), ActivityTime.range(am, pm))
    }
}

final class CityGazetteerTests: XCTestCase {
    func testEveryNamedPlaceIsInsideTheCity() {
        for p in NYCGeo.landmarks { XCTAssertTrue(NYCGeo.contains(p.coordinate), "landmark \(p.name)") }
        for n in NYCGeo.neighborhoods { XCTAssertTrue(NYCGeo.contains(n.coordinate), "neighborhood \(n.name)") }
        for p in SeedData.make(now: .now).activities {
            XCTAssertTrue(NYCGeo.contains(p.walk.from.coordinate) && NYCGeo.contains(p.walk.to.coordinate), p.title)
        }
    }

    func testEveryBoroughHasNeighborhoodsAndLandmarksToSearch() {
        let boroughs = Set(NYCGeo.landmarks.compactMap { NYCGeo.borough(of: $0.coordinate) })
        XCTAssertEqual(boroughs, ["Manhattan", "Brooklyn", "Queens", "The Bronx", "Staten Island"])
        XCTAssertEqual(NYCGeo.suggestions(matching: "prospect").first?.name, "Prospect Park (Brooklyn)")
        XCTAssertFalse(NYCGeo.suggestions(matching: "astoria").isEmpty)
        XCTAssertFalse(NYCGeo.suggestions(matching: "snug").isEmpty)
    }

    @MainActor func testCameraFacesGridOnlyInManhattan() {
        XCTAssertEqual(ExploreViewModel.heading(near: .init(40.7580, -73.9855)), ExploreViewModel.gridHeading)
        XCTAssertEqual(ExploreViewModel.heading(near: .init(40.6602, -73.9690)), 0)
    }
}
