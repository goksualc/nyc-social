import XCTest
import SwiftUI
@testable import Along

/// Guards the cause of the login/sign-up typing lag: the whole auth screen used to be re-rendered on every keystroke
/// because all the text lived in the parent's `@State`. Typing must now only touch the field being edited.
@MainActor
final class TypingPerformanceTests: XCTestCase {
    private func makeHost(form: AuthFormModel, mode: EmailAuthView.Mode) -> (UIHostingController<some View>, UIWindow) {
        let session = AppSession(services: .init(auth: DemoAuthService(), backend: MockAlongBackend(), realtime: nil),
                                 isLive: false, configProblem: nil)
        let root = NavigationStack { EmailAuthView(initialMode: mode, form: form) }.environment(session)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return (host, window)
    }

    private func typeAndMeasure(_ edit: (Int) -> Void, host: UIViewController, keystrokes: Int = 300) -> (perKeystrokeMs: Double, bodyRuns: Int) {
        let before = EmailAuthView.bodyEvaluations
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<keystrokes {
            edit(i)
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) / Double(keystrokes) * 1000
        return (ms, EmailAuthView.bodyEvaluations - before)
    }

    func testTypingInSignInDoesNotRerenderTheScreen() {
        let form = AuthFormModel()
        let (host, window) = makeHost(form: form, mode: .signIn)
        let result = typeAndMeasure({ i in
            if i % 2 == 0 { form.email += "a" } else { form.password += "b" }
        }, host: host)
        print("PERF sign-in: \(result.perKeystrokeMs) ms/keystroke, screen body runs: \(result.bodyRuns)")
        XCTAssertEqual(result.bodyRuns, 0, "typing must not re-evaluate the whole screen")
        XCTAssertLessThan(result.perKeystrokeMs, 8)
        _ = window
    }

    func testTypingInSignUpDoesNotRerenderTheScreen() {
        let form = AuthFormModel()
        let (host, window) = makeHost(form: form, mode: .signUp)
        let result = typeAndMeasure({ i in
            switch i % 4 { case 0: form.name += "a"; case 1: form.email += "b"; case 2: form.password += "c"; default: form.confirm += "d" }
        }, host: host)
        print("PERF sign-up: \(result.perKeystrokeMs) ms/keystroke, screen body runs: \(result.bodyRuns)")
        XCTAssertEqual(result.bodyRuns, 0)
        XCTAssertLessThan(result.perKeystrokeMs, 8)
        _ = window
    }

    func testSubmitButtonEnablesWhenFormIsFilled() {
        let form = AuthFormModel()
        XCTAssertFalse(form.isFilled(signUp: false))
        form.email = "a@b.co"; form.password = "secret123"
        XCTAssertTrue(form.isFilled(signUp: false))
        XCTAssertFalse(form.isFilled(signUp: true), "sign-up also needs a name and a confirmation")
        form.name = "Ada"; form.confirm = "secret123"
        XCTAssertTrue(form.isFilled(signUp: true))
    }
}
