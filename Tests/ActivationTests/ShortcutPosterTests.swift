import XCTest
@testable import Activation

final class ShortcutPosterTests: XCTestCase {
    func testSendNewWindowShortcutPostsToRunningApp() {
        let app = FakeRunningApplication(processIdentifier: 4321)
        var postedPID: pid_t?
        let poster = ShortcutPoster(
            runningApplications: { _ in [app] },
            postNewWindowShortcut: { pid in
                postedPID = pid
                return true
            }
        )

        let result = poster.sendNewWindowShortcut(toBundleID: "com.example.App")

        XCTAssertTrue(result)
        XCTAssertEqual(postedPID, 4321)
    }

    func testSendNewWindowShortcutReturnsFalseWhenAppIsMissing() {
        let poster = ShortcutPoster(
            runningApplications: { _ in [] },
            postNewWindowShortcut: { _ in
                XCTFail("should not try to post when the app is missing")
                return false
            }
        )

        let result = poster.sendNewWindowShortcut(toBundleID: "com.example.App")

        XCTAssertFalse(result)
    }
}

private final class FakeRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    var isActive: Bool
    let localizedName: String?

    init(processIdentifier: pid_t = 1234, isActive: Bool = false, localizedName: String? = "Fake App") {
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.localizedName = localizedName
    }

    func unhide() -> Bool {
        true
    }

    func activate(options _: NSApplication.ActivationOptions) -> Bool {
        isActive
    }
}
