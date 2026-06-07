import Activation
import AppKit
import XCTest
@testable import StayHereApp

private final class FakeRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    var isActive: Bool
    var localizedName: String?
    var activateResults: [Bool]
    var unhideCallCount = 0
    var activateCallCount = 0

    init(
        processIdentifier: pid_t = 55,
        isActive: Bool = false,
        localizedName: String? = "Notes",
        activateResults: [Bool]
    ) {
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.localizedName = localizedName
        self.activateResults = activateResults
    }

    @discardableResult
    func unhide() -> Bool {
        unhideCallCount += 1
        return true
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCallCount += 1
        let result = activateResults.isEmpty ? false : activateResults.removeFirst()
        if result {
            isActive = true
        }
        return result
    }
}

final class WindowFocusServiceTests: XCTestCase {
    private func waitForMainQueue(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "main-queue-drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    func testActivationSuccessStillRaisesTargetWindow() {
        let app = FakeRunningApplication(isActive: false, activateResults: [true])
        var raised = false
        var madeMain = false
        var unminimized = false
        let service = WindowFocusService(
            runningApplicationProvider: { _ in app },
            accessibilityWindowsProvider: { _ in
                [
                    WindowFocusTarget(
                        title: "Doc",
                        unminimize: { unminimized = true },
                        raise: { raised = true },
                        makeMain: { madeMain = true }
                    )
                ]
            },
            retryScheduler: { _ in XCTFail("Retry should not be scheduled on successful activation") },
            applicationActivator: {}
        )

        service.focusWindow(entry: WindowEntry(windowID: 1, pid: 55, appName: "Notes", windowTitle: "Doc", icon: NSImage()))
        waitForMainQueue()

        XCTAssertEqual(app.unhideCallCount, 1)
        XCTAssertEqual(app.activateCallCount, 1)
        XCTAssertTrue(unminimized)
        XCTAssertTrue(raised)
        XCTAssertTrue(madeMain)
    }

    func testActivationFailureRunsRetryPath() {
        let app = FakeRunningApplication(isActive: false, activateResults: [false, false])
        var retryScheduled = false
        var raiseCallCount = 0
        let service = WindowFocusService(
            runningApplicationProvider: { _ in app },
            accessibilityWindowsProvider: { _ in
                [
                    WindowFocusTarget(
                        title: "Doc",
                        unminimize: {},
                        raise: { raiseCallCount += 1 },
                        makeMain: {}
                    )
                ]
            },
            retryScheduler: { work in
                retryScheduled = true
                work()
            },
            applicationActivator: {}
        )

        service.focusWindow(entry: WindowEntry(windowID: 1, pid: 55, appName: "Notes", windowTitle: "Doc", icon: NSImage()))
        waitForMainQueue()

        XCTAssertTrue(retryScheduled)
        XCTAssertEqual(app.activateCallCount, 2)
        XCTAssertEqual(raiseCallCount, 2)
    }

    func testMinimizedWindowsAreUnminimizedBeforeRaise() {
        let app = FakeRunningApplication(isActive: true, activateResults: [true])
        var operations: [String] = []
        let service = WindowFocusService(
            runningApplicationProvider: { _ in app },
            accessibilityWindowsProvider: { _ in
                [
                    WindowFocusTarget(
                        title: "Doc",
                        unminimize: { operations.append("unminimize") },
                        raise: { operations.append("raise") },
                        makeMain: { operations.append("main") }
                    )
                ]
            },
            retryScheduler: { _ in },
            applicationActivator: {}
        )

        service.focusWindow(entry: WindowEntry(windowID: 1, pid: 55, appName: "Notes", windowTitle: "Doc", icon: NSImage()))
        waitForMainQueue()

        XCTAssertEqual(operations, ["unminimize", "raise", "main"])
    }

    func testFallsBackToFirstWindowWhenTitleDoesNotMatch() {
        let app = FakeRunningApplication(isActive: true, activateResults: [true])
        var firstRaised = false
        var secondRaised = false
        let service = WindowFocusService(
            runningApplicationProvider: { _ in app },
            accessibilityWindowsProvider: { _ in
                [
                    WindowFocusTarget(title: "Other", unminimize: {}, raise: { firstRaised = true }, makeMain: {}),
                    WindowFocusTarget(title: "Another", unminimize: {}, raise: { secondRaised = true }, makeMain: {})
                ]
            },
            retryScheduler: { _ in },
            applicationActivator: {}
        )

        service.focusWindow(entry: WindowEntry(windowID: 1, pid: 55, appName: "Notes", windowTitle: "Missing", icon: NSImage()))
        waitForMainQueue()

        XCTAssertTrue(firstRaised)
        XCTAssertFalse(secondRaised)
    }
}
