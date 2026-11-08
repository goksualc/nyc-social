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
        XCTAssertEqual("\(vm.camera)", cameraBefore, "opening the sheet must not move the map")
        vm.isClusterOpen = false
        XCTAssertTrue(vm.clusterWalks.isEmpty)
    }
}
