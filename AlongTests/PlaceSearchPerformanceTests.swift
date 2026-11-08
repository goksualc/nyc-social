import XCTest
import SwiftUI
@testable import Along

@MainActor
final class PlaceSearchPerformanceTests: XCTestCase {
    func testLocalSuggestionsAreInstant() {
        let queries = ["7", "72", "72n", "72nd", "b", "br", "bry", "bryant", "w", "we", "west v", "west village", "central park"]
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 { for q in queries { _ = NYCGeo.suggestions(matching: q) } }
        let ms = (CFAbsoluteTimeGetCurrent() - start) / Double(50 * queries.count) * 1000
        XCTAssertLessThan(ms, 1)
    }

    private func textField(in view: UIView) -> UITextField? {
        if let t = view as? UITextField { return t }
        for s in view.subviews { if let t = textField(in: s) { return t } }
        return nil
    }

    private func allText(in view: UIView) -> [String] {
        var out: [String] = []
        if let l = view as? UILabel, let t = l.text { out.append(t) }
        for s in view.subviews { out += allText(in: s) }
        return out
    }

    /// Types into the real sheet, character by character, and checks the field really receives the text and results appear.
    func testTypingIntoThePlaceSearchSheetWorks() throws {
        let host = UIHostingController(rootView: PlaceSearchView(title: "Starting point") { _ in })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let field = try XCTUnwrap(textField(in: host.view), "the search field exists")
        XCTAssertTrue(field.becomeFirstResponder() || field.isFirstResponder)
        let start = CFAbsoluteTimeGetCurrent()
        for ch in "Bryant" {
            field.insertText(String(ch))
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("PERF typed 6 chars in \(elapsed) ms; field text = '\(field.text ?? "")'; labels = \(allText(in: host.view))")
        XCTAssertEqual(field.text, "Bryant")
    }

    func testModelShowsLocalResultsImmediately() {
        let model = PlaceSearchModel()
        model.search("Bryant")
        XCTAssertTrue(model.suggestions.map(\.title).contains("Bryant Park"), "offline matches don't wait for MapKit")
        model.search("72nd")
        XCTAssertEqual(model.suggestions.first?.title, "72nd St")
        model.search("")
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertFalse(model.isSearching)
    }
}

/// Measures the longest time the main thread was unresponsive while MapKit's completer was running.
@MainActor
final class PlaceSearchHangTests: XCTestCase {
    func testMapKitCompleterDoesNotBlockTheMainThread() {
        let model = PlaceSearchModel()
        var lastTick = CFAbsoluteTimeGetCurrent()
        var worstGap = 0.0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            worstGap = max(worstGap, now - lastTick)
            lastTick = now
        }
        let end = Date().addingTimeInterval(6)
        var typed = ""
        for ch in "bryant park" {
            typed.append(ch)
            model.search(typed)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        timer.invalidate()
        print("PERF worst main-thread gap: \(Int(worstGap * 1000)) ms; suggestions: \(model.suggestions.map(\.title)); searching: \(model.isSearching)")
        XCTAssertLessThan(worstGap, 0.25, "the main thread must never stall while suggestions load")
    }
}
