import XCTest
@testable import Along

final class RouteSearchTests: XCTestCase {
    func testLabelsOnlyClaimWhatTheNumbersSupport() {
        let a = Activity(id: "a", title: "t", hostID: "h", walk: WalkInfo(from: NYCGeo.street(10), to: NYCGeo.street(20), pace: .casual),
                         startDate: .now, endDate: .now.addingTimeInterval(3600), visibility: .public, capacity: 2)
        func match(_ overlap: Double, dir: Double, s: Bool, e: Bool) -> RouteMatch {
            RouteMatch(activity: a, host: .anonymousHost(id: "anon:x", interests: []), overlap: overlap, routeDistanceMeters: 0,
                       directionDiffDegrees: dir, startsNear: s, endsNear: e, score: 0)
        }
        XCTAssertEqual(match(0.9, dir: 10, s: true, e: true).labels, ["Follows your route", "Starts and ends near you"])
        XCTAssertEqual(match(0.6, dir: 120, s: false, e: false).labels, ["Shares 60% of your route"])
        XCTAssertTrue(match(0.1, dir: 170, s: false, e: false).labels.isEmpty, "a weak, opposite-direction match gets no flattering label")
        XCTAssertEqual(match(0.35, dir: 20, s: false, e: true).labels, ["Ends near your destination", "Same direction"])
    }

    func testMockSearchRanksTheWalkAlongTheRouteFirst() async throws {
        let b = MockAlongBackend()
        let route = (10...30).map { NYCGeo.street($0).coordinate }
        let found = try await b.searchAlongRoute(RouteSearchQuery(route: route, corridorMeters: 300))
        XCTAssertFalse(found.isEmpty)
        XCTAssertEqual(found.map(\.score), found.map(\.score).sorted(by: >), "best match first")
        XCTAssertTrue(found.allSatisfy { $0.activity.visibility == .public })
        do { _ = try await b.searchAlongRoute(RouteSearchQuery(route: [route[0]])); XCTFail() } catch {}
    }
}

@MainActor
final class ClusterSheetTests: XCTestCase {
    func testTappingAClusterResolvesItsWalksAndKeepsTheCamera() async throws {
        let store = try await AppStore.bootstrap(backend: MockAlongBackend())
        await store.discover(ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: store.now))
        let vm = ExploreViewModel(store: store, location: LocationService())
        let cluster = vm.mapItems.compactMap { item -> ExploreViewModel.Cluster? in if case .cluster(let c) = item { return c }; return nil }.first
        let c = try XCTUnwrap(cluster, "the seed walks should form at least one cluster at the overview zoom")
        let cameraBefore = "\(vm.camera)"
        vm.openCluster(c)
        XCTAssertTrue(vm.isClusterOpen)
        XCTAssertTrue(vm.isHighlighted(c))
        XCTAssertEqual(Set(vm.clusterWalks.map(\.id)), Set(c.activities.map(\.id)))
        XCTAssertGreaterThanOrEqual(vm.clusterWalks.count, 2)
        XCTAssertEqual(vm.selectedID, vm.clusterWalks.first?.id, "the first card is selected, as a single pin would be")
        let second = vm.clusterWalks[1].id
        vm.page(to: second)
        XCTAssertEqual(vm.selectedID, second, "swiping selects the page's walk")
        XCTAssertTrue(vm.isHighlighted(c), "the cluster stays highlighted while paging")
        XCTAssertTrue(vm.mapItems.contains { if case .cluster(let k) = $0 { return k.id == c.id }; return false }, "the numbered marker doesn't split while its cards are open")
        XCTAssertEqual("\(vm.camera)", cameraBefore, "opening the sheet must not move the map")
        vm.deselect()
        XCTAssertTrue(vm.clusterWalks.isEmpty)
        XCTAssertNil(vm.selectedID)
    }
}

@MainActor
final class CreateWalkFormTests: XCTestCase {
    private func vm() async throws -> CreateActivityViewModel {
        CreateActivityViewModel(store: try await AppStore.bootstrap(backend: MockAlongBackend()))
    }

    func testTagsAreLimitedToThree() async throws {
        let vm = try await vm()
        for t in ["Tech", "Career", "Life", "Psychology"] { vm.toggleTag(t) }
        XCTAssertEqual(vm.tags, ["Tech", "Career", "Life"])
        vm.toggleTag("Career")
        XCTAssertEqual(vm.tags, ["Tech", "Life"], "tapping a chosen tag removes it")
    }

    func testHostModesMapToWhatTheServerStores() async throws {
        let vm = try await vm()
        vm.tags = ["Tech", "Life"]
        vm.hostMode = .publicHost
        XCTAssertFalse(vm.hostMode.hidesIdentity); XCTAssertEqual(vm.publishedTags, ["Tech", "Life"])
        vm.hostMode = .privateHost
        XCTAssertTrue(vm.hostMode.hidesIdentity); XCTAssertEqual(vm.publishedTags, ["Tech", "Life"])
        vm.hostMode = .anonymousHost
        XCTAssertTrue(vm.hostMode.hidesIdentity); XCTAssertTrue(vm.publishedTags.isEmpty, "Anonymous Host shares no tags")
    }

    func testPublishingKeepsTagsAndHidesTheHostOnlyWhenAsked() async throws {
        let store = try await AppStore.bootstrap(backend: MockAlongBackend())
        let vm = CreateActivityViewModel(store: store)
        vm.from = NYCGeo.street(40); vm.to = NYCGeo.street(60)
        vm.tags = ["Career", "Random Thoughts"]
        vm.mindPrompt = "Career thoughts"
        vm.hostMode = .privateHost
        let ok = await vm.publishWalk()
        XCTAssertTrue(ok)
        let mine = store.snapshot.activities.first { $0.hostID == store.me.id && $0.mindPrompt == "Career thoughts" }
        XCTAssertEqual(mine?.hostInterests, ["Career", "Random Thoughts"])
        XCTAssertEqual(mine?.hostAnonymous, true)
    }

    func testRouteLineReadsLikeTheDesign() async throws {
        let vm = try await vm()
        XCTAssertNil(vm.routeLine)
        vm.from = NYCGeo.street(40); vm.to = NYCGeo.street(14)
        await vm.updateRoute()
        let line = try XCTUnwrap(vm.routeLine)
        XCTAssertTrue(line.contains("→") && line.contains("min") && line.contains("miles"), line)
    }
}
