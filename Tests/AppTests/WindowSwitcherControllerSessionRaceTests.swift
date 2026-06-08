import XCTest
import CoreGraphics
import AppKit
import Core
@testable import StayHereApp

private final class LocalMockCGSBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int?
    var managedSnapshotValue: CGSBridge.ManagedSnapshot
    var activeSpaceIDCallCount = 0
    var managedSnapshotCallCount = 0

    init(
        activeSpaceIDValue: Int? = nil,
        managedSnapshotValue: CGSBridge.ManagedSnapshot = .init(
            spaces: [],
            activeByDisplay: [:],
            orderedIDsByDisplay: [:]
        )
    ) {
        self.activeSpaceIDValue = activeSpaceIDValue
        self.managedSnapshotValue = managedSnapshotValue
    }

    func activeSpaceID() -> Int? {
        activeSpaceIDCallCount += 1
        return activeSpaceIDValue
    }

    func managedSnapshot() -> CGSBridge.ManagedSnapshot {
        managedSnapshotCallCount += 1
        return managedSnapshotValue
    }

    func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
    func switchByDesktopShortcut(index: Int) -> Bool { true }
    func spacesForWindow(windowID: Int) -> [Int] { [] }
}

final class WindowSwitcherControllerSessionRaceTests: XCTestCase {
    private func makeController(
        windowInfo: @escaping () -> [[String: Any]]? = { [] },
        focusService: WindowFocusService = WindowFocusService()
    ) -> (WindowSwitcherController, LocalMockCGSBridge) {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 100, display: "display-a", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 100],
            orderedIDsByDisplay: ["display-a": [100]]
        )
        let bridge = LocalMockCGSBridge(
            activeSpaceIDValue: 100,
            managedSnapshotValue: snapshot
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowSwitcherControllerSessionRaceTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let registry = SpaceRegistry(store: store, cgsBridge: bridge)
        let listProvider = WindowListProvider(
            registry: registry,
            cgsBridge: bridge,
            settings: UserDefaultsSettingsRepository(),
            windowInfoProvider: windowInfo,
            runningApplicationProvider: { _ in nil },
            accessibilityWindowTitlesProvider: { _ in [:] },
            iconProvider: { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        )
        let controller = WindowSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            cgsBridge: bridge,
            listProvider: listProvider,
            focusService: focusService
        )
        return (controller, bridge)
    }

    private func makeController() -> (WindowSwitcherController, LocalMockCGSBridge) {
        makeController(windowInfo: { [] })
    }

    private func makeKeyEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags = []
    ) -> CGEvent {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        )!
        event.flags = flags
        return event
    }

    private func waitForMainQueue(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "main-queue-drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    /// Regression test for C2/C3/C10/C11: pressing the configured shortcut should
    /// create a session via the main thread.
    func testHandleKeyDownCreatesSessionOnMainThread() {
        let (controller, _) = makeController()
        // ⌘` (keyCode 50)
        let event = makeKeyEvent(keyCode: 50, flags: .maskCommand)

        _ = controller.handle(event: event)
        waitForMainQueue()

        XCTAssertTrue(controller.hasActiveSession, "Session should be created after first ⌘` key down")
    }

    /// Regression test for C3: cancelSession called from a background thread
    /// (simulating the event-tap thread) must marshal the session reset to main
    /// thread and not leave a stale session.
    func testCancelSessionFromBackgroundThreadEventuallyNilsSession() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        // Simulate cancel from a background thread (e.g., the event-tap thread).
        let cancelExpectation = expectation(description: "cancel")
        DispatchQueue.global(qos: .userInitiated).async {
            controller.cancelSession()
            DispatchQueue.main.async { cancelExpectation.fulfill() }
        }

        wait(for: [cancelExpectation], timeout: 1.0)
        // After cancelSession's main-async block runs, session should be nil
        XCTAssertFalse(controller.hasActiveSession, "Session should be nil after cancelSession on main thread")
    }

    /// Regression test for C11: handleFlagsChanged must dispatch the session reset
    /// to the main thread, even when called from the event-tap thread.
    func testHandleFlagsChangedMarshalsSessionResetToMainThread() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        // The flags-changed handler inspects `event.flags` to decide whether the
        // session-modifying modifiers are still held. We pass a keyDown event with
        // empty flags so the controller interprets this as "modifiers released".
        let flagsReleased = makeKeyEvent(keyCode: 50, flags: [])

        // Simulate being called from the event-tap thread.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = controller.handleFlagsChanged(event: flagsReleased)
        }

        let exp = expectation(description: "flags-changed-handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(controller.hasActiveSession, "Session should be nil after handleFlagsChanged on main thread")
    }

    /// Regression test for C2/C10: rapid keyDown events on a background thread
    /// must not corrupt session state. The session should never leak.
    func testRapidKeyDownDoesNotLeakSession() {
        let (controller, _) = makeController()

        let keyDownEvent = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        let drainExpectation = expectation(description: "drain")

        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<20 {
                _ = controller.handle(event: keyDownEvent)
            }
            DispatchQueue.main.async { drainExpectation.fulfill() }
        }

        wait(for: [drainExpectation], timeout: 1.0)
        // We don't make a hard assertion about whether a session exists (depends
        // on whether the test thread raced the main thread), only that no crash
        // occurred and the controller remains in a valid state — verifiable by
        // dispatching one more cycle.
        DispatchQueue.main.async { [weak controller] in
            _ = controller?.handle(event: keyDownEvent)
        }
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession, "A session should exist after a clean key-down on main thread")
    }

    // MARK: - Caching (P2/Q5)

    /// P2/Q5: a session's entries should be populated when the session opens.
    func testSessionEntriesAreCachedOnEnsureSession() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertTrue(controller.hasActiveSession)
        XCTAssertNotNil(controller.testSessionEntries, "Session must cache the window list on creation")
    }

    /// P2/Q5: the session must remember the space context it was opened with.
    func testSessionSpaceContextIsCachedOnEnsureSession() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testSessionSpaceID, 100, "Session must cache the space context (100) on creation")
    }

    /// P2/Q5: rapid keypresses must keep the same entries array (cached).
    /// We verify the cgsBridge `managedSnapshot` and `activeSpaceID`
    /// methods are NOT re-invoked on every keypress — that's the perf
    /// win from caching the entries + spaceContext in `Session`.
    func testMoveSelectionDoesNotRecomputeEntries() {
        let (controller, bridge) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)

        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        let snapshotCallsAfterFirst = bridge.managedSnapshotCallCount
        let activeSpaceCallsAfterFirst = bridge.activeSpaceIDCallCount
        XCTAssertGreaterThan(snapshotCallsAfterFirst, 0, "First keypress must populate the cache")
        XCTAssertGreaterThan(activeSpaceCallsAfterFirst, 0, "First keypress must populate the cache")

        // Fire several more keyDowns to drive moveSelection repeatedly.
        for _ in 0..<5 {
            _ = controller.handle(event: keyDown)
        }
        waitForMainQueue()

        XCTAssertEqual(
            bridge.managedSnapshotCallCount, snapshotCallsAfterFirst,
            "managedSnapshot must NOT be called on subsequent keypresses (cached in Session)"
        )
        XCTAssertEqual(
            bridge.activeSpaceIDCallCount, activeSpaceCallsAfterFirst,
            "activeSpaceID must NOT be called on subsequent keypresses (cached in Session)"
        )
    }

    /// P2/Q5: opening a new session must re-fetch the window list. The
    /// cache is per-session and is rebuilt on session creation.
    func testNewSessionRebuildsCache() {
        let (controller, bridge) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)

        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        let firstSnapshotCalls = bridge.managedSnapshotCallCount
        let firstActiveSpaceCalls = bridge.activeSpaceIDCallCount

        // Close the session and open a new one.
        controller.cancelSession()
        waitForMainQueue()

        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertGreaterThan(
            bridge.managedSnapshotCallCount, firstSnapshotCalls,
            "Opening a new session must re-fetch the snapshot"
        )
        XCTAssertGreaterThan(
            bridge.activeSpaceIDCallCount, firstActiveSpaceCalls,
            "Opening a new session must re-fetch the active space id"
        )
    }

    /// P2/Q5: cancelSession must clear the cached entries (no leak across
    /// consecutive switcher sessions).
    func testCancelSessionClearsCachedEntries() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)

        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertNotNil(controller.testSessionEntries)

        controller.cancelSession()
        waitForMainQueue()

        XCTAssertNil(controller.testSessionEntries, "Cancel must drop the cached entries")
    }

    func testPanelHeightAllowsMoreThanTenRowsWhenScreenHasRoom() {
        let height = WindowSwitcherController.panelHeight(itemCount: 14, screenHeight: 1000)

        XCTAssertEqual(height, 634, "Taller screens should allow more than the previous ten visible rows")
    }

    func testPanelHeightStillCapsToAvailableScreenHeight() {
        let height = WindowSwitcherController.panelHeight(itemCount: 30, screenHeight: 700)

        XCTAssertEqual(height, 620, "Panel height should stop at the available visible screen height")
    }

    func testModifierReleaseCommitsSelectedWindowEvenWhenSelectionMatchesStartingWindow() {
        var focusCallCount = 0
        let observedFocusService = WindowFocusService(
            runningApplicationProvider: { _ in nil },
            accessibilityWindowsProvider: { _ in [] },
            retryScheduler: { _ in },
            applicationActivator: { focusCallCount += 1 }
        )
        let (controller, _) = makeController(
            windowInfo: {
                [[
                    kCGWindowOwnerPID as String: NSNumber(value: 42),
                    kCGWindowNumber as String: NSNumber(value: 1),
                    kCGWindowLayer as String: NSNumber(value: 0),
                    kCGWindowIsOnscreen as String: NSNumber(value: true),
                    kCGWindowOwnerName as String: "Notes",
                    "kCGWindowWorkspace": NSNumber(value: 1),
                    kCGWindowName as String: "Doc"
                ]]
            },
            focusService: observedFocusService
        )

        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [1])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)

        controller.switcherCommitOrDismissActiveSession()
        waitForMainQueue()
        waitForMainQueue()

        XCTAssertEqual(focusCallCount, 1, "Releasing modifiers should still commit the selected entry even if it matches the starting window")
        XCTAssertFalse(controller.hasActiveSession)
    }
}
