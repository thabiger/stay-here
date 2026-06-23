import XCTest
import CoreGraphics
import Core
@testable import StayHereApp

private final class LocalMockCGSBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int?
    var managedSnapshotValue: CGSBridge.ManagedSnapshot

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

    func activeSpaceID() -> Int? { activeSpaceIDValue }
    func managedSnapshot() -> CGSBridge.ManagedSnapshot { managedSnapshotValue }
    func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
    func switchByDesktopShortcut(index: Int) -> Bool { true }
    func spacesForWindow(windowID: Int) -> [Int] { [] }
}

@MainActor
final class SpaceSwitcherControllerSessionRaceTests: XCTestCase {
    private func makeController(
        activeSpaceID: Int = 100,
        additionalSpaces: [Int] = [101, 102]
    ) -> (SpaceSwitcherController, LocalMockCGSBridge) {
        let spaces = [activeSpaceID] + additionalSpaces
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: spaces.map { SpaceIdentity(id: $0, display: "display-a", kind: .desktop) },
            activeByDisplay: ["display-a": activeSpaceID],
            orderedIDsByDisplay: ["display-a": spaces]
        )
        let bridge = LocalMockCGSBridge(
            activeSpaceIDValue: activeSpaceID,
            managedSnapshotValue: snapshot
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceSwitcherControllerSessionRaceTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let registry = SpaceRegistry(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let controller = SpaceSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            switchToSpace: { _ in }
        )
        return (controller, bridge)
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
        let event = makeKeyEvent(keyCode: 48, flags: .maskCommand) // ⌘Tab

        _ = controller.handle(event: event)
        waitForMainQueue()

        XCTAssertTrue(controller.hasActiveSession, "Session should be created after first ⌘Tab key down")
    }

    /// Regression test for C3: cancelSession called from a background thread
    /// (simulating the event-tap thread) must marshal the session reset to main
    /// thread and not leave a stale session.
    func testCancelSessionFromBackgroundThreadEventuallyNilsSession() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 48, flags: .maskCommand)
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
    /// We invoke the method directly because CGEvent cannot be constructed as
    /// a `.flagsChanged` type in a test environment.
    func testHandleFlagsChangedMarshalsSessionResetToMainThread() {
        let (controller, _) = makeController()
        let keyDown = makeKeyEvent(keyCode: 48, flags: .maskCommand)
        _ = controller.handle(event: keyDown)
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        // The flags-changed handler inspects `event.flags` to decide whether the
        // session-modifying modifiers are still held. We pass a keyDown event with
        // empty flags so the controller interprets this as "modifiers released".
        let flagsReleased = makeKeyEvent(keyCode: 48, flags: [])

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

        let keyDownEvent = makeKeyEvent(keyCode: 48, flags: .maskCommand)
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
        // The final state should be that the session exists OR was created
        // cleanly; either is fine, but it must not be in an inconsistent state.
        XCTAssertTrue(controller.hasActiveSession, "A session should exist after a clean key-down on main thread")
    }

    func testOpenSwitcherStartsSessionWithoutMovingSelection() {
        let (controller, _) = makeController(activeSpaceID: 100, additionalSpaces: [101, 102])

        controller.openSwitcher()
        waitForMainQueue()

        XCTAssertTrue(controller.hasActiveSession, "Explicit open should create a visible session without requiring held modifiers")
    }

    func testCloseSwitcherDismissesActiveSession() {
        let (controller, _) = makeController()
        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        controller.closeSwitcher()

        XCTAssertFalse(controller.hasActiveSession, "Explicit close should dismiss the session immediately")
    }

    func testSwitcherClosesWhenPanelLosesFocus() {
        let (controller, _) = makeController()

        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession)

        controller.panelPair?.window.resignKey()

        XCTAssertFalse(controller.hasActiveSession, "Losing focus should dismiss the switcher session")
    }

    func testExplicitSessionIgnoresNonMatchingKeyAndSupportsRepeatedMoves() {
        let (controller, _) = makeController(activeSpaceID: 100, additionalSpaces: [101, 102])

        controller.openSwitcher()
        waitForMainQueue()
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 100)

        _ = controller.handleKeyDown(event: makeKeyEvent(keyCode: 12, flags: .maskCommand))
        waitForMainQueue()
        XCTAssertTrue(controller.hasActiveSession, "Explicitly opened session should stay alive across unrelated key presses")

        controller.moveSelectionForward()
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 101)

        controller.moveSelectionForward()
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 102)
    }

    func testExplicitSessionCommitUsesCurrentSelection() {
        var switchedSpaceIDs: [Int] = []
        let spaces = [100, 101, 102]
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: spaces.map { SpaceIdentity(id: $0, display: "display-a", kind: .desktop) },
            activeByDisplay: ["display-a": 100],
            orderedIDsByDisplay: ["display-a": spaces]
        )
        let bridge = LocalMockCGSBridge(activeSpaceIDValue: 100, managedSnapshotValue: snapshot)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceSwitcherControllerSessionRaceTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let registry = SpaceRegistry(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let controller = SpaceSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            switchToSpace: { switchedSpaceIDs.append($0) }
        )

        controller.openSwitcher()
        waitForMainQueue()
        controller.moveSelectionForward()
        controller.moveSelectionForward()
        controller.commitSwitcherSelection()
        waitForMainQueue()

        XCTAssertEqual(switchedSpaceIDs, [102], "Explicit commit should switch to the currently selected space")
        XCTAssertFalse(controller.hasActiveSession)
    }

    func testExplicitSessionSupportsPanelKeyboardShortcuts() throws {
        var switchedSpaceIDs: [Int] = []
        let spaces = [100, 101, 102]
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: spaces.map { SpaceIdentity(id: $0, display: "display-a", kind: .desktop) },
            activeByDisplay: ["display-a": 100],
            orderedIDsByDisplay: ["display-a": spaces]
        )
        let bridge = LocalMockCGSBridge(activeSpaceIDValue: 100, managedSnapshotValue: snapshot)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceSwitcherControllerSessionRaceTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let registry = SpaceRegistry(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let controller = SpaceSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            switchToSpace: { switchedSpaceIDs.append($0) }
        )

        controller.openSwitcher()
        waitForMainQueue()

        let panel = try XCTUnwrap(controller.panelPair?.window as? SwitcherPanel)
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 100)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 125))
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 101)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 126))
        XCTAssertEqual(controller.testSessionSelectedSpaceID, 100)

        XCTAssertTrue(panel.handleKeyPress(keyCode: 36))
        waitForMainQueue()
        waitForMainQueue()
        XCTAssertEqual(switchedSpaceIDs, [100])
        XCTAssertFalse(controller.hasActiveSession)

        controller.openSwitcher()
        waitForMainQueue()
        let reopenedPanel = try XCTUnwrap(controller.panelPair?.window as? SwitcherPanel)
        XCTAssertTrue(reopenedPanel.handleKeyPress(keyCode: 53))
        XCTAssertFalse(controller.hasActiveSession)
    }
}
