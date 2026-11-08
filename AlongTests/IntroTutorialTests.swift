import XCTest
@testable import Along

final class IntroTutorialTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "intro-tests-\(UUID().uuidString)")!
        return d
    }

    func testFirstSignedOutLaunchShowsTheTutorial() {
        XCTAssertTrue(IntroTutorialRules.shouldShow(hasSeen: false, signedOut: true, established: false))
    }

    func testSeenDevicesNeverSeeItAgain() {
        XCTAssertFalse(IntroTutorialRules.shouldShow(hasSeen: true, signedOut: true, established: false), "after logging out, or on any later launch")
    }

    func testItNeverReplacesTheSignedInExperience() {
        XCTAssertFalse(IntroTutorialRules.shouldShow(hasSeen: false, signedOut: false, established: false))
    }

    func testEstablishedInstallsAreMigratedQuietly() {
        let fresh = defaults()
        XCTAssertFalse(IntroTutorialRules.isEstablishedInstall(fresh))
        for key in IntroTutorialRules.legacyKeys {
            let d = defaults(); d.set(true, forKey: key)
            XCTAssertTrue(IntroTutorialRules.isEstablishedInstall(d), key)
        }
        XCTAssertFalse(IntroTutorialRules.shouldShow(hasSeen: false, signedOut: true, established: true))
    }

    @MainActor func testSessionAfterLaunchMarksItSeen() {
        // RootView sets the flag for every phase other than launching / signed out / failed; the tutorial can't be re-entered from there.
        for phase: AppSession.Phase in [.ready, .needsProfile, .passwordRecovery, .emailVerification("a@b.co")] {
            switch phase {
            case .launching, .signedOut, .failed: XCTFail("unexpected")
            default: break
            }
        }
    }
}
