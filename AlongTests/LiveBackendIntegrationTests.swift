import XCTest
@testable import Along

/// Runs the real `SupabaseBackend` against PostgREST + PostGIS built from `supabase/migrations`, as three separate
/// users. Skipped unless launched through `supabase/tests/run_integration.sh` (which provides the environment).
/// Covers the full journey: profile → create → discover → request → accept (with a capacity race) → chat → block → edit → cancel.
final class LiveBackendIntegrationTests: XCTestCase {
    struct Actor {
        let id: ID
        let backend: SupabaseBackend
    }

    private func actor(_ letter: String) throws -> Actor {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["ALONG_IT_URL"], let jwt = env["ALONG_IT_JWT_\(letter)"], let uid = env["ALONG_IT_USER_\(letter)"] else {
            throw XCTSkip("Integration environment not configured (run supabase/tests/run_integration.sh)")
        }
        // The "publishable key" slot carries each user's pre-minted JWT, so every request is authenticated as them.
        let config = try SupabaseConfig.validate(url: url, key: jwt).get()
        return Actor(id: uid, backend: SupabaseBackend(manager: SupabaseManager(config: config, userIDOverride: uid)))
    }

    private func draft(_ name: String) -> ProfileDraft {
        ProfileDraft(displayName: name, bio: "Hi, I'm \(name)", interests: [.coffee, .walking], alongFor: [.walkingBuddies], confirmAge: true)
    }

    private var manhattanBox: DiscoveryQuery {
        ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: .now)
    }

    func testFullUserJourneyWithThreeAccounts() async throws {
        let a = try actor("A"), b = try actor("B"), c = try actor("C")

        // ---- profiles
        let before = try await a.backend.loadMyProfile()
        XCTAssertFalse(before.isComplete, "new users start incomplete")
        XCTAssertEqual(before.fullName, "Ada Lovelace", "metadata name captured by the trigger")
        try await a.backend.completeProfile(draft("Ada"), fullName: nil)
        try await b.backend.completeProfile(draft("Bea"), fullName: nil)
        try await c.backend.completeProfile(draft("Cy"), fullName: nil)
        let after = try await a.backend.loadMyProfile()
        XCTAssertTrue(after.isComplete)
        XCTAssertEqual(after.user.firstName, "Ada")
        XCTAssertEqual(after.user.interests, [.coffee, .walking])

        // ---- A publishes a walk (with a real route) and a cowork session
        let from = ManhattanGeo.street(72), to = ManhattanGeo.street(55)
        let route = (0...20).map { i -> Coordinate in
            let t = Double(i) / 20
            return Coordinate(from.coordinate.latitude + (to.coordinate.latitude - from.coordinate.latitude) * t,
                              from.coordinate.longitude + (to.coordinate.longitude - from.coordinate.longitude) * t)
        }
        let start = Date().addingTimeInterval(3 * 3600)
        let walkDraft = ActivityDraft(title: "Evening walk to Midtown", details: .walk(WalkInfo(from: from, to: to, pace: .casual)),
                                      startDate: start, endDate: start.addingTimeInterval(3600), visibility: .public, capacity: 1,
                                      note: "Getting my steps in", meetingDetails: "South-west corner of 72nd & Broadway", routeCoordinates: route)
        var snapA = try await a.backend.createActivity(walkDraft)
        let walk = try XCTUnwrap(snapA.activities.first { $0.title == "Evening walk to Midtown" })
        XCTAssertTrue(walk.hasPreciseAccess)
        XCTAssertEqual(walk.meetingDetails, "South-west corner of 72nd & Broadway")
        XCTAssertEqual(walk.routeCoordinates.count, 21, "host gets the saved route back")
        XCTAssertEqual(walk.walk?.from.coordinate.latitude ?? 0, from.coordinate.latitude, accuracy: 1e-6, "host sees exact start")

        var cafe = ManhattanGeo.cafes[0]; cafe.address = "142 Prince St"
        let coStart = Date().addingTimeInterval(5 * 3600)
        snapA = try await a.backend.createActivity(ActivityDraft(
            title: "Working from SoHo", details: .cowork(CoworkInfo(venue: cafe, style: .deepWork)), startDate: coStart,
            endDate: coStart.addingTimeInterval(4 * 3600), visibility: .public, capacity: 2, note: "Startup stuff", meetingDetails: "Big table"))
        let privateStart = Date().addingTimeInterval(6 * 3600)
        snapA = try await a.backend.createActivity(ActivityDraft(
            title: "Secret session", details: .cowork(CoworkInfo(venue: ManhattanGeo.cafes[1], style: .social)), startDate: privateStart,
            endDate: privateStart.addingTimeInterval(3600), visibility: .private, capacity: 1, note: "", meetingDetails: ""))
        XCTAssertEqual(snapA.activities.count, 3)

        // ---- validation happens server-side too
        let outside = Place(name: "Prospect Park", area: "", coordinate: Coordinate(40.6602, -73.9690))
        do {
            _ = try await a.backend.createActivity(ActivityDraft(title: "x", details: .cowork(CoworkInfo(venue: outside, style: .social)), startDate: start,
                                                                  endDate: start.addingTimeInterval(3600), visibility: .public, capacity: 1, note: "", meetingDetails: ""))
            XCTFail("outside Manhattan accepted")
        } catch { XCTAssertEqual(ErrorPresenter.map(error), .outsideManhattan) }
        do {
            var past = walkDraft; past.startDate = Date().addingTimeInterval(-7200); past.endDate = Date().addingTimeInterval(-3600)
            _ = try await a.backend.createActivity(past)
            XCTFail("past walk accepted")
        } catch { XCTAssertEqual(ErrorPresenter.map(error), .startInPast) }

        // ---- B discovers (public, approximate only)
        let page = try await b.backend.discover(manhattanBox)
        XCTAssertEqual(Set(page.activities.map(\.title)), ["Evening walk to Midtown", "Working from SoHo"], "private plan is never discoverable")
        let seenWalk = try XCTUnwrap(page.activities.first { $0.id == walk.id })
        XCTAssertFalse(seenWalk.hasPreciseAccess)
        XCTAssertEqual(seenWalk.meetingDetails, "")
        XCTAssertNotEqual(seenWalk.walk?.from.coordinate, from.coordinate, "public start is snapped, not exact")
        XCTAssertLessThan(seenWalk.walk?.from.coordinate.distance(to: from.coordinate) ?? .infinity, 400)
        XCTAssertEqual(seenWalk.publicLocationLabel, "72nd St → 55th St")
        let seenCowork = try XCTUnwrap(page.activities.first { $0.title == "Working from SoHo" })
        XCTAssertEqual(seenCowork.cowork?.venue.name, "", "café name is hidden until accepted")
        XCTAssertEqual(seenCowork.spotsLeft, 2)
        XCTAssertEqual(page.hosts.first?.firstName, "Ada")

        var walksOnly = manhattanBox; walksOnly.kind = .walk
        let walksPage = try await b.backend.discover(walksOnly)
        XCTAssertEqual(walksPage.activities.map(\.title), ["Evening walk to Midtown"])
        var paged = manhattanBox; paged.limit = 1
        let first = try await b.backend.discover(paged)
        XCTAssertEqual(first.activities.count, 1); XCTAssertTrue(first.hasMore)
        paged.offset = 1
        let second = try await b.backend.discover(paged)
        XCTAssertEqual(second.activities.count, 1); XCTAssertFalse(second.hasMore)
        var soho = manhattanBox; soho.minLat = 40.715; soho.maxLat = 40.730; soho.minLng = -74.010; soho.maxLng = -73.990
        let sohoPage = try await b.backend.discover(soho)
        XCTAssertTrue(sohoPage.activities.allSatisfy { $0.kind == .cowork }, "bounding box excludes the uptown walk start")
        let near = try await b.backend.nearby(to: ManhattanGeo.street(72).coordinate, radiusMeters: 1500, kind: nil, limit: 10)
        XCTAssertEqual(near.activities.map(\.title), ["Evening walk to Midtown"])

        // ---- B requests; duplicates and own-plan requests are refused
        var snapB = try await b.backend.requestToJoin(activityID: walk.id)
        XCTAssertEqual(snapB.requests.first { $0.activityID == walk.id }?.status, .pending)
        do { _ = try await b.backend.requestToJoin(activityID: walk.id); XCTFail("duplicate allowed") }
        catch { XCTAssertEqual(ErrorPresenter.map(error), .alreadyRequested) }
        do { _ = try await a.backend.requestToJoin(activityID: walk.id); XCTFail("own plan allowed") }
        catch { XCTAssertEqual(ErrorPresenter.map(error), .notAllowed) }
        snapB = try await b.backend.withdrawRequest(activityID: walk.id)
        XCTAssertEqual(snapB.requests.filter { $0.activityID == walk.id }.last?.status, .withdrawn)
        snapB = try await b.backend.requestToJoin(activityID: walk.id)             // allowed again after cancelling
        _ = try await c.backend.requestToJoin(activityID: walk.id)

        // ---- A sees both requests (with requester profiles) and approves exactly one (capacity 1)
        snapA = try await a.backend.loadSnapshot()
        let pending = snapA.requests.filter { $0.activityID == walk.id && $0.status == .pending }
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(Set(pending.compactMap { r in snapA.users.first { $0.id == r.requesterID }?.firstName }), ["Bea", "Cy"])
        let requestB = try XCTUnwrap(pending.first { $0.requesterID == b.id })
        let requestC = try XCTUnwrap(pending.first { $0.requesterID == c.id })

        let taskB = Task { try await a.backend.respond(requestID: requestB.id, accept: true) }
        let taskC = Task { try await a.backend.respond(requestID: requestC.id, accept: true) }
        let outcomes = [await taskB.result, await taskC.result]
        XCTAssertEqual(outcomes.filter { if case .success = $0 { true } else { false } }.count, 1, "exactly one approval wins the last spot")
        let loser = outcomes.compactMap { r -> AlongError? in if case .failure(let e) = r { ErrorPresenter.map(e) } else { nil } }
        XCTAssertEqual(loser, [.activityFull])

        snapA = try await a.backend.loadSnapshot()
        let accepted = snapA.requests.filter { $0.activityID == walk.id && $0.status == .accepted }
        XCTAssertEqual(accepted.count, 1)
        let guest = try XCTUnwrap(accepted.first?.requesterID)
        XCTAssertEqual(snapA.activities.first { $0.id == walk.id }?.spotsLeft, 0)
        XCTAssertEqual(snapA.conversations.count, 1)
        let guestBackend = guest == b.id ? b.backend : c.backend
        let other = guest == b.id ? c : b

        // ---- accepted guest unlocks precise details + chat; the other can't see them
        let snapGuest = try await guestBackend.loadSnapshot()
        let unlocked = try XCTUnwrap(snapGuest.activities.first { $0.id == walk.id })
        XCTAssertTrue(unlocked.hasPreciseAccess)
        XCTAssertEqual(unlocked.meetingDetails, "South-west corner of 72nd & Broadway")
        XCTAssertEqual(unlocked.walk?.from.coordinate.latitude ?? 0, from.coordinate.latitude, accuracy: 1e-6)
        XCTAssertEqual(snapGuest.conversations.count, 1)
        let snapOther = try await other.backend.loadSnapshot()
        XCTAssertEqual(snapOther.conversations.count, 0, "non-participants can't see the conversation")
        XCTAssertEqual(snapOther.activities.first { $0.id == walk.id }?.meetingDetails ?? "", "")

        let convo = try XCTUnwrap(snapGuest.conversations.first)
        let m1 = try await guestBackend.sendMessage(conversationID: convo.id, text: "  Hello Ada!  ")
        XCTAssertEqual(m1.text, "Hello Ada!"); XCTAssertEqual(m1.senderID, guest)
        let m2 = try await a.backend.sendMessage(conversationID: convo.id, text: "Welcome!")
        XCTAssertEqual(m2.senderID, a.id)
        do { _ = try await other.backend.sendMessage(conversationID: convo.id, text: "intruding"); XCTFail("outsider sent a message") }
        catch { XCTAssertEqual(ErrorPresenter.map(error), .chatClosed) }
        let latest = try await a.backend.loadMessages(conversationID: convo.id, before: nil, limit: 1)
        XCTAssertEqual(latest.map(\.text), ["Welcome!"])
        let older = try await a.backend.loadMessages(conversationID: convo.id, before: latest[0].sentAt, limit: 10)
        XCTAssertEqual(older.map(\.text), ["Hello Ada!"], "pagination returns the page before the cursor")

        // ---- host edits the plan
        snapA = try await a.backend.updateActivity(ActivityEdit(activityID: walk.id, startDate: nil, endDate: nil, capacity: 2,
                                                                note: "Updated note", meetingDetails: "By the subway steps"))
        XCTAssertEqual(snapA.activities.first { $0.id == walk.id }?.capacity, 2)
        XCTAssertEqual(snapA.activities.first { $0.id == walk.id }?.meetingDetails, "By the subway steps")
        do {
            _ = try await a.backend.updateActivity(ActivityEdit(activityID: walk.id, startDate: nil, endDate: nil, capacity: 0, note: nil, meetingDetails: nil))
            XCTFail("capacity 0 accepted")
        } catch { XCTAssertNotNil(error) }
        do {
            _ = try await guestBackend.updateActivity(ActivityEdit(activityID: walk.id, startDate: nil, endDate: nil, capacity: 5, note: nil, meetingDetails: nil))
            XCTFail("guest edited someone else's plan")
        } catch { XCTAssertEqual(ErrorPresenter.map(error), .notFound) }

        // ---- guest leaves → chat closes, history stays
        let afterLeave = try await guestBackend.leave(activityID: walk.id)
        XCTAssertNotEqual(afterLeave.requests.last { $0.activityID == walk.id && $0.requesterID == guest }?.status, .accepted)
        do { _ = try await guestBackend.sendMessage(conversationID: convo.id, text: "still here?"); XCTFail("chat stayed open") }
        catch { XCTAssertEqual(ErrorPresenter.map(error), .chatClosed) }
        let history = try await guestBackend.loadMessages(conversationID: convo.id, before: nil, limit: 10)
        XCTAssertEqual(history.count, 2)

        // ---- blocking hides everything both ways
        let blocked = try await b.backend.block(userID: a.id)
        XCTAssertTrue(blocked.blockedUserIDs.contains(a.id))
        XCTAssertEqual(blocked.users.first { $0.id == a.id }?.firstName, "Ada", "blocked list keeps a name snapshot")
        let bDiscover = try await b.backend.discover(manhattanBox)
        XCTAssertFalse(bDiscover.activities.contains { $0.hostID == a.id })
        let aSees = try await a.backend.discover(manhattanBox)
        XCTAssertTrue(aSees.activities.isEmpty || !aSees.activities.contains { $0.hostID == b.id })
        do { _ = try await b.backend.requestToJoin(activityID: seenCowork.id); XCTFail("requested a blocked host's plan") }
        catch { XCTAssertEqual(ErrorPresenter.map(error), .notFound) }
        let unblocked = try await b.backend.unblock(userID: a.id)
        XCTAssertFalse(unblocked.blockedUserIDs.contains(a.id))

        // ---- reports are accepted
        try await b.backend.report(.user(a.id), reason: .spam)
        try await b.backend.report(.activity(walk.id), reason: .unsafe)

        // ---- cancel
        snapA = try await a.backend.cancelActivity(id: seenCowork.id)
        XCTAssertTrue(snapA.activities.first { $0.id == seenCowork.id }?.isCancelled == true)
        let afterCancel = try await b.backend.discover(manhattanBox)
        XCTAssertFalse(afterCancel.activities.contains { $0.id == seenCowork.id }, "cancelled plans leave discovery")

        // ---- profile edits round-trip
        var me = try await b.backend.loadSnapshot().me
        me.bio = "Updated bio"; me.interests = [.art]
        let saved = try await b.backend.updateProfile(me)
        XCTAssertEqual(saved.bio, "Updated bio")
        let reloaded = try await b.backend.loadMyProfile()
        XCTAssertEqual(reloaded.user.interests, [.art])
        var settings = UserSettings(); settings.profileVisibility = .activityMembers
        try await b.backend.updateSettings(settings)
        let reloadedVisibility = try await b.backend.loadMyProfile().visibility
        XCTAssertEqual(reloadedVisibility, .activityMembers)

        // ---- Cy (restricted profile? no) can't read Bea's now-restricted profile unless they share a plan
        let cySnap = try await c.backend.loadSnapshot()
        XCTAssertNil(cySnap.users.first { $0.id == b.id && !$0.bio.isEmpty }, "restricted profile hidden from strangers")
    }
}
