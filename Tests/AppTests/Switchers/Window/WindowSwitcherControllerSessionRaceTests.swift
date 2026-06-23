import XCTest
import CoreGraphics
import AppKit
import Activation
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

private final class LocalFakeRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    var isActive: Bool
    var localizedName: String? = "Notes"
    var activateResults: [Bool]

    init(
        processIdentifier: pid_t = 55,
        isActive: Bool,
        activateResults: [Bool]
    ) {
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        self.activateResults = activateResults
    }

    @discardableResult
    func unhide() -> Bool {
        true
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        let result = activateResults.isEmpty ? false : activateResults.removeFirst()
        if result {
            isActive = true
        }
        return result
    }
}

final class WindowSwitcherControllerSessionRaceTests: XCTestCase {
    private func makeController(
        windowInfo: @escaping () -> [[String: Any]]? = { [] },
        focusedWindowID: @escaping () -> Int? = { nil },
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
        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let registry = SpaceRegistry(repository: repository)
        let refreshSpaces = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())
        let switchSpace = SwitchSpaceUseCase(cgsBridge: bridge, repository: repository, refreshUseCase: refreshSpaces, logger: NoOpLogger())
        let listProvider = WindowListProvider(
            registry: registry,
            cgsBridge: bridge,
            settings: UserDefaultsSettingsRepository(),
            windowInfoProvider: windowInfo,
            runningApplicationProvider: { _ in nil },
            accessibilityWindowTitlesProvider: { _ in [:] },
            focusedWindowIDProvider: focusedWindowID,
            iconProvider: { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        )
        let windowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: bridge,
            listProvider: listProvider,
            switchSpace: switchSpace,
            refreshSpaces: refreshSpaces,
            focusService: focusService
        ))
        let controller = WindowSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            mode: .currentSpace,
            windowSwitchUseCase: windowSwitchUseCase,
            cgsBridge: bridge,
            listProvider: listProvider
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

    private func makeWindow(
        pid: pid_t,
        windowID: Int,
        ownerName: String = "Notes",
        title: String = "Doc"
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowNumber as String: NSNumber(value: windowID),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
            kCGWindowOwnerName as String: ownerName,
            "kCGWindowWorkspace": NSNumber(value: 1),
            kCGWindowName as String: title
        ]
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

    func testOpeningSessionOrdersPreviousWindowFirstAndSelectsIt() {
        let (controller, _) = makeController {
            [
                self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                self.makeWindow(pid: 43, windowID: 2, title: "Previous"),
                self.makeWindow(pid: 44, windowID: 3, title: "Older")
            ]
        }

        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [2, 1, 3])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)
    }

    func testOpeningSessionUsesFocusedWindowAsCurrentWhenSystemListIsStable() {
        let (controller, _) = makeController(
            windowInfo: {
                [
                    self.makeWindow(pid: 42, windowID: 1, title: "Stable First"),
                    self.makeWindow(pid: 43, windowID: 2, title: "Stable Second"),
                    self.makeWindow(pid: 44, windowID: 3, title: "Focused")
                ]
            },
            focusedWindowID: { 3 }
        )

        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testRecentWindowIDs, [3, 1, 2])
        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [1, 3, 2])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)
    }

    func testCommittedSelectionReordersNextSessionEvenWhenSystemListDoesNotChange() {
        let stableWindowInfo: () -> [[String: Any]]? = {
            [
                self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                self.makeWindow(pid: 43, windowID: 2, title: "Previous"),
                self.makeWindow(pid: 44, windowID: 3, title: "Older")
            ]
        }
        let (controller, _) = makeController(windowInfo: stableWindowInfo)
        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)

        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [2, 1, 3])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)

        controller.switcherCommitOrDismissActiveSession()
        waitForMainQueue()
        waitForMainQueue()
        XCTAssertEqual(controller.testRecentWindowIDs, [2, 1, 3])

        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [1, 2, 3])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)
    }

    func testRepeatedShortcutMovesForwardFromPreviousToCurrentWindow() {
        let (controller, _) = makeController {
            [
                self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                self.makeWindow(pid: 43, windowID: 2, title: "Previous"),
                self.makeWindow(pid: 44, windowID: 3, title: "Older")
            ]
        }

        let keyDown = makeKeyEvent(keyCode: 50, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        _ = controller.handle(event: keyDown)
        waitForMainQueue()

        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [2, 1, 3])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)
    }

    func testSwitcherClosesWhenPanelLosesFocus() {
        let (controller, _) = makeController {
            [
                self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                self.makeWindow(pid: 43, windowID: 2, title: "Previous")
            ]
        }

        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        controller.panelPair?.window.resignKey()

        XCTAssertFalse(controller.hasActiveSession, "Losing focus should dismiss the switcher session")
    }

    func testExplicitSessionSupportsPanelKeyboardShortcuts() throws {
        let app = LocalFakeRunningApplication(isActive: true, activateResults: [true])
        var raisedWindowTitles: [String?] = []
        let focusService = WindowFocusService(
            runningApplicationProvider: { _ in app },
            accessibilityWindowsProvider: { _ in
                [
                    WindowFocusTarget(
                        title: "Current",
                        unminimize: {},
                        raise: { raisedWindowTitles.append("Current") },
                        makeMain: {}
                    ),
                    WindowFocusTarget(
                        title: "Previous",
                        unminimize: {},
                        raise: { raisedWindowTitles.append("Previous") },
                        makeMain: {}
                    ),
                    WindowFocusTarget(
                        title: "Older",
                        unminimize: {},
                        raise: { raisedWindowTitles.append("Older") },
                        makeMain: {}
                    )
                ]
            },
            retryScheduler: { _ in },
            applicationActivator: {}
        )
        let (controller, _) = makeController(
            windowInfo: {
                [
                    self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                    self.makeWindow(pid: 43, windowID: 2, title: "Previous"),
                    self.makeWindow(pid: 44, windowID: 3, title: "Older")
                ]
            },
            focusService: focusService
        )

        controller.openSwitcher()
        waitForMainQueue()

        let panel = try XCTUnwrap(controller.panelPair?.window as? SwitcherPanel)
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 125))
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 126))
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 36))
        waitForMainQueue()
        waitForMainQueue()
        XCTAssertEqual(raisedWindowTitles, ["Previous"])
        XCTAssertFalse(controller.hasActiveSession)

        controller.openSwitcher()
        waitForMainQueue()
        let reopenedPanel = try XCTUnwrap(controller.panelPair?.window as? SwitcherPanel)
        XCTAssertTrue(reopenedPanel.handleKeyPress(keyCode: 53))
        XCTAssertFalse(controller.hasActiveSession)
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
        let height = WindowSwitcherPanelLayout.panelHeight(spaceGroupCount: 0, totalWindowCount: 14, screenHeight: 1000)

        XCTAssertEqual(height, 634, "Taller screens should allow more than the previous ten visible rows")
    }

    func testPanelHeightStillCapsToAvailableScreenHeight() {
        let height = WindowSwitcherPanelLayout.panelHeight(spaceGroupCount: 0, totalWindowCount: 30, screenHeight: 700)

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

    func testOpenSwitcherStartsSessionWithoutMovingSelection() {
        let (controller, _) = makeController {
            [
                self.makeWindow(pid: 42, windowID: 1, title: "Current"),
                self.makeWindow(pid: 43, windowID: 2, title: "Previous"),
                self.makeWindow(pid: 44, windowID: 3, title: "Older")
            ]
        }

        controller.openSwitcher()
        waitForMainQueue()

        XCTAssertTrue(controller.hasActiveSession, "Explicit open should create a visible session without requiring held modifiers")
        XCTAssertEqual(controller.testSessionEntries?.map(\.windowID), [2, 1, 3])
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)
    }

    func testCloseSwitcherDismissesActiveSession() {
        let (controller, _) = makeController()
        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        controller.closeSwitcher()

        XCTAssertFalse(controller.hasActiveSession, "Explicit close should dismiss the session immediately")
    }

    func testExplicitSessionIgnoresNonMatchingKeyAndSupportsRepeatedMoves() {
        let windows: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 42),
                kCGWindowNumber as String: NSNumber(value: 1),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowOwnerName as String: "Notes",
                "kCGWindowWorkspace": NSNumber(value: 1),
                kCGWindowName as String: "Doc 1"
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 42),
                kCGWindowNumber as String: NSNumber(value: 2),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowOwnerName as String: "Notes",
                "kCGWindowWorkspace": NSNumber(value: 1),
                kCGWindowName as String: "Doc 2"
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 42),
                kCGWindowNumber as String: NSNumber(value: 3),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowOwnerName as String: "Notes",
                "kCGWindowWorkspace": NSNumber(value: 1),
                kCGWindowName as String: "Doc 3"
            ]
        ]
        let (controller, _) = makeController(windowInfo: { windows })

        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertEqual(controller.testSessionSelectedWindowID, 2)

        _ = controller.handleKeyDown(event: makeKeyEvent(keyCode: 12, flags: .maskCommand))
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession, "Explicitly opened session should stay alive across unrelated key presses")

        controller.moveSelectionForward()
        XCTAssertEqual(controller.testSessionSelectedWindowID, 1)

        controller.moveSelectionForward()
        XCTAssertEqual(controller.testSessionSelectedWindowID, 3)
    }
}
