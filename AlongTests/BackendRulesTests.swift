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
        let soho = snap.activities.first { $0.id == "act-soho" }!
        XCTAssertFalse(soho.hasPreciseAccess)
        XCTAssertEqual(soho.meetingDetails, "")
        XCTAssertEqual(soho.cowork?.venue.name, "", "venue name is withheld")
        let exact = SeedData.make(now: .now).activities.first { $0.id == "act-soho" }!.cowork!.venue.coordinate
        XCTAssertNotEqual(soho.cowork?.venue.coordinate, exact)
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
        let snap = try await backend().block(userID: "alex")
        XCTAssertFalse(snap.activities.contains { $0.hostID == "alex" })
        XCTAssertFalse(snap.requests.contains { $0.activityID == "act-soho" })
        let snap2 = try await backend().block(userID: "emma")
        XCTAssertFalse(snap2.requests.contains { $0.requesterID == "emma" })
        let snap3 = try await backend().block(userID: "priya")
        XCTAssertFalse(snap3.conversations.contains { $0.participantIDs.contains("priya") })
    }

    func testCreateValidatesManhattanAndTimes() async throws {
        let b = backend()
        let manhattan = ManhattanGeo.street(40)
        let brooklyn = Place(name: "Prospect Park", area: "", coordinate: .init(40.6602, -73.9690))
        func draft(_ d: ActivityDetails, start: Date = .now.addingTimeInterval(3600)) -> ActivityDraft {
            ActivityDraft(title: "t", details: d, startDate: start, endDate: start.addingTimeInterval(3600),
                          visibility: .public, capacity: 2, note: "", meetingDetails: "")
        }
        do { _ = try await b.createActivity(draft(.cowork(.init(venue: brooklyn, style: .social)))); XCTFail() } catch AlongError.outsideManhattan {}
        do { _ = try await b.createActivity(draft(.cowork(.init(venue: manhattan, style: .social)), start: .now.addingTimeInterval(-7200))); XCTFail() } catch AlongError.startInPast {}
        let snap = try await b.createActivity(draft(.walk(.init(from: ManhattanGeo.street(40), to: ManhattanGeo.street(60), pace: .fast))))
        XCTAssertEqual(snap.activities.count, SeedData.make(now: .now).activities.count + 1)
    }

    func testPrivatePlansAreCreatedButNeverDiscoverable() async throws {
        let b = backend()
        let d = ActivityDraft(title: "Private", details: .cowork(.init(venue: ManhattanGeo.cafes[0], style: .deepWork)),
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
        let snap = await backend().simulateHostResponse(activityID: "act-soho")
        XCTAssertEqual(snap.requests.first { $0.id == "req-me-soho" }?.status, .accepted)
        XCTAssertTrue(snap.activities.first { $0.id == "act-soho" }!.hasPreciseAccess)
    }
}

final class GeoAndTimeTests: XCTestCase {
    func testManhattanBoundary() {
        XCTAssertTrue(ManhattanGeo.contains(.init(40.7580, -73.9855)))   // Times Square
        XCTAssertTrue(ManhattanGeo.contains(.init(40.7794, -73.9632)))   // The Met
        XCTAssertTrue(ManhattanGeo.contains(.init(40.7358, -74.0036)))   // West Village
        XCTAssertFalse(ManhattanGeo.contains(.init(40.6782, -73.9442)))  // Brooklyn
        XCTAssertFalse(ManhattanGeo.contains(.init(40.7282, -73.7949)))  // Queens
        XCTAssertFalse(ManhattanGeo.contains(.init(40.7178, -74.0431)))  // Jersey City
        for p in SeedData.make(now: .now).activities { XCTAssertTrue(ManhattanGeo.contains(Coordinate(p.mapCoordinate)), p.title) }
    }

    func testApproximateCoordinateIsCoarse() {
        let c = Coordinate(40.77371, -73.96634)
        XCTAssertGreaterThan(c.distance(to: c.approximate), 0)
        XCTAssertLessThan(c.distance(to: c.approximate), 400)
    }

    func testStreetsAndOrdinals() {
        XCTAssertEqual(ManhattanGeo.ordinal(72), "72nd"); XCTAssertEqual(ManhattanGeo.ordinal(11), "11th")
        XCTAssertEqual(ManhattanGeo.street(55).name, "55th St")
        XCTAssertEqual(ManhattanGeo.suggestions(matching: "72").first?.name, "72nd St")
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
