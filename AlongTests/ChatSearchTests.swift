import XCTest
import UIKit
@testable import Along

@MainActor
final class ChatSearchTests: XCTestCase {
    private func vm() async throws -> InboxViewModel {
        InboxViewModel(store: try await AppStore.bootstrap(backend: MockAlongBackend()))
    }

    func testRobotoFacesAreRegisteredUnderTheirPostScriptNames() {
        for name in [AlongRoboto.regular, AlongRoboto.medium, AlongRoboto.bold] {
            XCTAssertNotNil(UIFont(name: name, size: 17), "\(name) is not registered — check UIAppFonts and the file's PostScript name")
        }
    }

    func testSearchMatchesNameMessageAndWalkTitleIgnoringCase() async throws {
        let vm = try await vm()
        vm.filter = .all
        let everything = vm.visibleConversations
        XCTAssertFalse(everything.isEmpty)

        vm.query = "JONAS"                                   // participant name, upper case
        XCTAssertEqual(vm.visibleConversations.map(\.id), ["conv-jonas"])

        vm.query = "looking forward"                         // the message preview (latest message)
        XCTAssertTrue(vm.visibleConversations.contains { $0.id == "conv-jonas" })

        vm.query = "morning central park"                    // the walk's title
        XCTAssertTrue(vm.visibleConversations.contains { $0.id == "conv-jonas" })

        vm.query = "zzzz-nothing"
        XCTAssertTrue(vm.visibleConversations.isEmpty)

        vm.query = "   "                                      // whitespace is not a search
        XCTAssertEqual(vm.visibleConversations.map(\.id), everything.map(\.id))
        vm.query = ""
        XCTAssertEqual(vm.visibleConversations.map(\.id), everything.map(\.id), "clearing restores the full list, in the same order")
    }

    func testSearchKeepsOrderingAndUnreadState() async throws {
        let vm = try await vm()
        vm.query = "a"
        let hits = vm.visibleConversations
        let all = vm.conversations
        XCTAssertEqual(hits.map(\.id), all.filter { hits.map(\.id).contains($0.id) }.map(\.id), "filtering never reorders")
        for c in hits { XCTAssertEqual(vm.isUnread(c), vm.store.isUnread(c)) }
    }
}
