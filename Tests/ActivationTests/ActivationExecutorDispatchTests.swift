import XCTest
import Core
@testable import Activation

final class ActivationExecutorDispatchTests: XCTestCase {
    func testLaunchDispatchesToAppActivator() {
        let appURL = URL(fileURLWithPath: "/Applications/Fake.app")
        var openedURL: URL?
        let appActivator = AppActivator(
            runningApplications: { _ in [] },
            appURL: { _ in appURL },
            openApplication: { url, _, completion in
                openedURL = url
                completion(nil)
            }
        )
        let executor = ActivationExecutor(appActivator: appActivator)

        let handled = executor.execute(decision: .launch, context: makeContext())

        XCTAssertTrue(handled)
        XCTAssertEqual(openedURL, appURL)
    }

    func testFocusCurrentSpaceDispatchesToAppActivator() {
        let app = FakeRunningApplication()
        let appActivator = AppActivator(
            runningApplications: { _ in [app] },
            appURL: { _ in nil },
            openApplication: { _, _, completion in completion(nil) }
        )
        let executor = ActivationExecutor(appActivator: appActivator)

        let handled = executor.execute(decision: .focusCurrentSpace, context: makeContext())

        XCTAssertTrue(handled)
        XCTAssertEqual(app.unhideCallCount, 1)
        XCTAssertEqual(app.activateCallCount, 1)
    }

    func testCreateNewWindowDispatchesToFocusAndShortcutPoster() {
        let app = FakeRunningApplication()
        var postedPID: pid_t?
        let appActivator = AppActivator(
            runningApplications: { _ in [app] },
            appURL: { _ in nil },
            openApplication: { _, _, completion in completion(nil) }
        )
        let shortcutPoster = ShortcutPoster(
            runningApplications: { _ in [app] },
            postNewWindowShortcut: { pid in
                postedPID = pid
                return true
            }
        )
        let executor = ActivationExecutor(appActivator: appActivator, shortcutPoster: shortcutPoster)

        let handled = executor.execute(decision: .createNewWindow, context: makeContext())

        XCTAssertTrue(handled)
        XCTAssertEqual(app.activateCallCount, 1)
        XCTAssertEqual(postedPID, app.processIdentifier)
    }

    func testSingleWindowHintUsesDisplayNameFromAppActivator() {
        let app = FakeRunningApplication(localizedName: "Notes")
        var shownHint: String?
        let appActivator = AppActivator(
            runningApplications: { _ in [app] },
            appURL: { _ in nil },
            openApplication: { _, _, completion in completion(nil) }
        )
        let executor = ActivationExecutor(
            showSingleWindowHint: { shownHint = $0 },
            appActivator: appActivator
        )

        let handled = executor.execute(decision: .singleWindowHint, context: makeContext())

        XCTAssertTrue(handled)
        XCTAssertEqual(
            shownHint,
            "Notes was clicked. It is configured as a single-window app. Use Option+Click to switch to the space where it is running."
        )
    }

    func testConsumeOnlyReturnsTrueAndPassthroughReturnsFalse() {
        let executor = ActivationExecutor()

        XCTAssertTrue(executor.execute(decision: .consumeOnly, context: makeContext()))
        XCTAssertFalse(executor.execute(decision: .passthrough, context: makeContext()))
    }

    private func makeContext() -> ActivationContext {
        ActivationContext(
            bundleID: "com.example.App",
            activeSpaceIDs: [1],
            targetSpaceID: 1,
            appWindowSummary: nil,
            singleWindowSpaceID: 1,
            optionHeld: false
        )
    }
}

private final class FakeRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    var isActive: Bool
    let localizedName: String?
    var unhideCallCount = 0
    var activateCallCount = 0

    init(processIdentifier: pid_t = 1234, isActive: Bool = false, localizedName: String? = "Fake App") {
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.localizedName = localizedName
    }

    func unhide() -> Bool {
        unhideCallCount += 1
        return true
    }

    func activate(options _: NSApplication.ActivationOptions) -> Bool {
        activateCallCount += 1
        return isActive
    }
}
