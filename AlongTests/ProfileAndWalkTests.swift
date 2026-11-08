import XCTest
import CoreLocation
import Supabase
@testable import Along

final class SocialNetworkTests: XCTestCase {
    func testInstagramUsernamesAreValidatedAndNormalised() {
        let ig = SocialNetwork.instagram
        XCTAssertEqual(ig.username(from: "@emma.walks"), "emma.walks")
        XCTAssertEqual(ig.username(from: "  emma_w  "), "emma_w")
        XCTAssertEqual(ig.username(from: "https://www.instagram.com/emma.walks/?hl=en"), "emma.walks")
        XCTAssertEqual(ig.username(from: "instagram.com/emma"), "emma")
        XCTAssertNil(ig.username(from: ".leading"))
        XCTAssertNil(ig.username(from: "trailing."))
        XCTAssertNil(ig.username(from: "double..dot"))
        XCTAssertNil(ig.username(from: "has space"))
        XCTAssertNil(ig.username(from: String(repeating: "a", count: 31)))
        XCTAssertNil(ig.username(from: "https://evil.example/emma"), "other hosts are rejected")
        XCTAssertNil(ig.username(from: ""))
    }

    func testXUsernamesAreValidatedAndNormalised() {
        let x = SocialNetwork.x
        XCTAssertEqual(x.username(from: "@goksu"), "goksu")
        XCTAssertEqual(x.username(from: "https://twitter.com/goksu"), "goksu")
        XCTAssertEqual(x.username(from: "x.com/goksu_1"), "goksu_1")
        XCTAssertNil(x.username(from: "dots.not.allowed"))
        XCTAssertNil(x.username(from: "waytoolongusername1"), "X usernames are at most 15 characters")
    }

    func testCanonicalProfileURLsOnlyForValidUsernames() {
        XCTAssertEqual(SocialNetwork.instagram.profileURL(for: "emma.walks")?.absoluteString, "https://instagram.com/emma.walks")
        XCTAssertEqual(SocialNetwork.x.profileURL(for: "goksu")?.absoluteString, "https://x.com/goksu")
        XCTAssertNil(SocialNetwork.x.profileURL(for: "../../evil"))
        XCTAssertNil(SocialNetwork.instagram.profileURL(for: "a b"))
    }

    func testCustomHobbiesAreCleaned() {
        XCTAssertEqual(HobbyCatalog.cleaned("  urban   sketching "), "urban sketching")
        XCTAssertNil(HobbyCatalog.cleaned("   "))
        XCTAssertEqual(HobbyCatalog.cleaned(String(repeating: "x", count: 80))?.count, HobbyCatalog.maxCustomLength)
    }
}

final class ProfileDecodingTests: XCTestCase {
    func testDetailedProfileRowMapsToUser() throws {
        let json = """
        {"id":"u1","display_name":"Emma","bio":"Hi","visibility":"everyone","hobbies":["Walking","Urban sketching"],
         "instagram_username":"emma.walks","x_username":null,"occupation":"Designer","languages":["English","French"],
         "favorite_neighborhoods":["Chelsea"],"preferred_pace":"slow","preferred_duration":45,"favorite_mode":"both",
         "discussion_topics":["career"],"conversation_custom":["Cities"]}
        """
        let user = try SupabaseCoding.makeDecoder().decode(ProfileRow.self, from: Data(json.utf8)).user
        XCTAssertEqual(user.hobbies, ["Walking", "Urban sketching"])
        XCTAssertEqual(user.instagram, "emma.walks")
        XCTAssertNil(user.xHandle)
        XCTAssertEqual(user.pacePreference, .slow)
        XCTAssertEqual(user.preferredDuration, 45)
        XCTAssertEqual(user.discussionTopics, [.career])
    }

    func testProfilesFromOlderServersStillDecode() throws {
        let json = #"{"id":"u1","display_name":"Old","bio":"","visibility":"everyone"}"#
        let user = try SupabaseCoding.makeDecoder().decode(ProfileRow.self, from: Data(json.utf8)).user
        XCTAssertEqual(user.firstName, "Old")
        XCTAssertTrue(user.hobbies.isEmpty)
    }

    func testOwnProfileWithoutOnboardingFlagIsTreatedAsOnboarded() throws {
        let json = #"{"id":"u1","display_name":"Old","age_confirmed_at":"2026-10-28T10:00:00+00:00","visibility":"everyone"}"#
        let row = try SupabaseCoding.makeDecoder().decode(MyProfileRow.self, from: Data(json.utf8))
        XCTAssertNil(row.onboardingCompleted, "servers before migration 8 send no flag; the app defaults to onboarded")
    }
}

final class WalkSessionModelTests: XCTestCase {
    func testSessionJSONFromTheServerDecodes() throws {
        let json = """
        {"id":"s1","activity_id":"a1","status":"ready_to_start","started_at":null,"ended_at":null,"duration_seconds":null,
         "distance_meters":null,"completion_deadline":null,
         "participants":[{"user_id":"h","role":"host","display_name":"Göksu","avatar_path":null,"joined_at":"2026-11-06T17:00:00.5+00:00",
                          "ready_at":null,"completion_confirmed_at":null,"sharing_stopped_at":null},
                         {"user_id":"g","role":"guest","display_name":"Emma","avatar_path":null,"joined_at":null,
                          "ready_at":null,"completion_confirmed_at":null,"sharing_stopped_at":null}]}
        """
        let s = try SupabaseCoding.makeDecoder().decode(WalkSession.self, from: Data(json.utf8))
        XCTAssertEqual(s.status, .readyToStart)
        XCTAssertEqual(s.partner(of: "h")?.displayName, "Emma")
        XCTAssertEqual(s.participant("h")?.isReady, false)
        XCTAssertTrue(s.status.isOpen)
        XCTAssertFalse(s.status.isLive)
    }

    func testEveryStatusRoundTrips() {
        for raw in ["awaiting_participants", "ready_to_start", "active", "awaiting_completion", "completed", "cancelled", "ended_early", "expired"] {
            XCTAssertNotNil(WalkSessionStatus(rawValue: raw), raw)
        }
    }

    func testMarkerTrackInterpolatesBetweenRealFixesOnly() {
        var track = MarkerTrack()
        let a = CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0)
        let b = CLLocationCoordinate2D(latitude: 40.001, longitude: -73.001)
        let t0 = Date()
        track.move(to: a, now: t0)
        XCTAssertEqual(track.coordinate(at: t0)?.latitude, 40.0)
        track.move(to: b, now: t0)
        let mid = track.coordinate(at: t0.addingTimeInterval(0.5))!
        XCTAssertGreaterThan(mid.latitude, 40.0)
        XCTAssertLessThan(mid.latitude, 40.001)
        // never extrapolates past the latest fix
        XCTAssertEqual(track.coordinate(at: t0.addingTimeInterval(30))?.latitude ?? 0, 40.001, accuracy: 1e-9)
        XCTAssertFalse(track.isAnimating(at: t0.addingTimeInterval(30)))
    }

    func testDistanceAndDurationFormatting() {
        XCTAssertEqual(DistanceFormat.miles(1609.344), "1.0 mi")
        XCTAssertEqual(DistanceFormat.duration(32 * 60), "32 min")
        XCTAssertEqual(DistanceFormat.duration(75 * 60), "1h 15m")
    }
}

/// The demo backend implements the same session rules as the server, so the UI flow can be exercised without a project.
final class MockWalkSessionTests: XCTestCase {
    /// Pinned to 9 AM so the seeded "today 5 PM" walk is always still ahead, whatever time the tests run.
    private func backend() -> MockAlongBackend {
        MockAlongBackend(clock: { Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600) })
    }

    func testSessionOpensOnlyForAcceptedParticipants() async throws {
        let b = backend()
        // act-midtown: I host, Priya is accepted → allowed
        let s = try await b.openSession(activityID: "act-midtown")
        XCTAssertEqual(s.participants.count, 2)
        // act-chelsea: I'm neither host nor guest → refused
        do { _ = try await b.openSession(activityID: "act-chelsea"); XCTFail("stranger opened a session") } catch AlongError.notAllowed {}
    }

    func testOpeningTwiceReturnsTheSameSession() async throws {
        let b = backend()
        let a = try await b.openSession(activityID: "act-midtown")
        let c = try await b.openSession(activityID: "act-midtown")
        XCTAssertEqual(a.id, c.id, "duplicate open requests must not create a second session")
    }

    func testReadyStartsTheWalkOnceAndIsIdempotent() async throws {
        let b = backend()
        let s = try await b.openSession(activityID: "act-midtown")
        let started = try await b.setReady(sessionID: s.id)
        XCTAssertEqual(started.status, .active)
        let again = try await b.setReady(sessionID: s.id)
        XCTAssertEqual(again.startedAt, started.startedAt, "a repeated press doesn't restart the walk")
    }

    func testStopSharingTakesEffectImmediately() async throws {
        let b = backend()
        let s = try await b.setReady(sessionID: try await b.openSession(activityID: "act-midtown").id)
        let stopped = try await b.setSharing(sessionID: s.id, enabled: false)
        XCTAssertFalse(stopped.participant("me")!.isSharing)
        let resumed = try await b.setSharing(sessionID: s.id, enabled: true)
        XCTAssertTrue(resumed.participant("me")!.isSharing)
    }

    func testFinishCompletesAndAppearsInHistoryWithClampedDistance() async throws {
        let b = backend()
        let s = try await b.setReady(sessionID: try await b.openSession(activityID: "act-midtown").id)
        let done = try await b.finish(sessionID: s.id, distanceMeters: 5_000_000)
        XCTAssertEqual(done.status, .completed)
        XCTAssertLessThan(done.distanceMeters ?? .max, 5_000_000, "an implausible reported distance is clamped")
        let history = try await b.history()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, s.id)
        XCTAssertNil(history.first?.partnerName, "partner names stay hidden until both opt in")
        let stats = try await b.stats()
        XCTAssertEqual(stats.walks, 1)
    }

    func testEndedEarlyIsNeverCounted() async throws {
        let b = backend()
        let s = try await b.setReady(sessionID: try await b.openSession(activityID: "act-midtown").id)
        let ended = try await b.endEarly(sessionID: s.id)
        XCTAssertEqual(ended.status, .endedEarly)
        let history = try await b.history()
        XCTAssertTrue(history.isEmpty)
        do { _ = try await b.setSharing(sessionID: s.id, enabled: true); XCTFail("sharing resumed after the walk ended") } catch AlongError.sessionClosed {}
    }

    func testTwoAcceptedGuestsCannotOpenALiveSession() async throws {
        let b = backend()
        _ = try await b.respond(requestID: "req-emma", accept: true)   // Priya + Emma are now both accepted
        do { _ = try await b.openSession(activityID: "act-midtown"); XCTFail("group session allowed") } catch AlongError.sessionRequiresTwo {}
    }

    func testMemoryPrivacyIsPerPersonAndPrivateByDefault() async throws {
        let b = backend()
        let s = try await b.setReady(sessionID: try await b.openSession(activityID: "act-midtown").id)
        _ = try await b.finish(sessionID: s.id, distanceMeters: nil)
        var walk = try await b.history().first!
        XCTAssertFalse(walk.showOnProfile)
        XCTAssertFalse(walk.revealPartner)
        try await b.setMemoryPrefs(sessionID: s.id, showOnProfile: true, revealPartner: nil)
        walk = try await b.history().first!
        XCTAssertTrue(walk.showOnProfile)
        XCTAssertFalse(walk.revealPartner)
    }
}

final class OutOfDateBackendTests: XCTestCase {
    func testMissingFunctionIsReportedAsAnOutdatedBackendNotAGenericFailure() {
        for code in ["PGRST202", "42883", "PGRST204", "42703"] {
            let error = PostgrestError(detail: nil, hint: nil, code: code, message: "Could not find the function")
            XCTAssertEqual(ErrorPresenter.map(error), .backendOutOfDate, code)
        }
        XCTAssertTrue(ErrorPresenter.message(for: PostgrestError(detail: nil, hint: nil, code: "PGRST202", message: "x"), fallback: "fallback").contains("migrations"))
    }
}
