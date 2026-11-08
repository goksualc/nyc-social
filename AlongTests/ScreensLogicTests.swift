import XCTest
@testable import Along

@MainActor
final class ScreensLogicTests: XCTestCase {
    private func store() async throws -> AppStore {
        UserDefaults.standard.removeObject(forKey: "along.lastRead.me")
        return try await AppStore.bootstrap(backend: MockAlongBackend(clock: { Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600) }))
    }

    // MARK: Inbox: unread

    func testUnreadComesFromTheOtherPersonAndClearsWhenOpened() async throws {
        let store = try await store()
        let chat = try XCTUnwrap(store.conversation(id: "conv-priya"))        // Priya sent the last message
        XCTAssertTrue(store.isUnread(chat))
        XCTAssertEqual(store.unreadConversationCount, 1, "only Priya's chat; I sent the last message in Jonas's")
        store.markRead(chat)
        XCTAssertFalse(store.isUnread(chat))
        XCTAssertEqual(store.unreadConversationCount, 0)
    }

    func testMyOwnLastMessageIsNeverUnread() async throws {
        let store = try await store()
        let chat = try XCTUnwrap(store.conversation(id: "conv-jonas"))        // I sent the last message there
        XCTAssertEqual(store.lastMessage(in: chat)?.senderID, "me")
        XCTAssertFalse(store.isUnread(chat))
    }

    func testInboxFilters() async throws {
        let store = try await store()
        let vm = InboxViewModel(store: store)
        vm.filter = .all
        XCTAssertEqual(vm.visibleConversations.count, 2)
        vm.filter = .unread
        XCTAssertEqual(vm.visibleConversations.map(\.id), ["conv-priya"])
        vm.filter = .requests
        XCTAssertTrue(vm.visibleConversations.isEmpty, "Requests shows request cards, not chats")
        XCTAssertEqual(vm.pendingCount, store.pendingIncomingCount)
    }

    // MARK: Walks: search and filters

    func testWalksUpcomingIncludesMyPlansAndPublicWalks() async throws {
        let store = try await store()
        await store.discover(ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: store.now))
        let vm = PlansViewModel(store: store)
        let ids = Set(vm.entries.map(\.id))
        XCTAssertTrue(ids.contains("act-midtown"), "my own plan")
        XCTAssertTrue(ids.contains("act-chelsea"), "someone else's public walk")
        XCTAssertEqual(vm.entries.count, ids.count, "no duplicates")
        XCTAssertEqual(vm.entries.first?.id, vm.featured?.id)
        XCTAssertFalse(vm.rest.contains { $0.id == vm.featured?.id })
    }

    func testWalksFiltersAndSearch() async throws {
        let store = try await store()
        await store.discover(ExploreViewModel.query(region: ExploreViewModel.overviewRegion, filter: .all, now: store.now))
        let vm = PlansViewModel(store: store)

        XCTAssertFalse(vm.entries.isEmpty)
        vm.filter = .upcoming
        vm.query = "careers"                              // matches a title
        XCTAssertEqual(vm.entries.map(\.id), ["act-careers"])
        XCTAssertNil(vm.featured, "no featured card while searching")
        vm.query = "central park"                         // matches a route label
        XCTAssertTrue(vm.entries.contains { $0.id == "act-park" })
        vm.query = "Emma"                                 // matches a host
        XCTAssertTrue(vm.entries.allSatisfy { store.host(of: $0.activity)?.firstName == "Emma" })
        vm.query = "zzzz-no-such-thing"
        XCTAssertTrue(vm.entries.isEmpty)

        vm.query = ""
        vm.filter = .past
        XCTAssertTrue(vm.entries.allSatisfy { !$0.activity.isActive(at: store.now) || $0.role == .declined })
    }
}
