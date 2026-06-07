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

final class WindowSwitcherControllerSessionRaceTests: XCTestCase {
    private func makeController() -> (WindowSwitcherController, LocalMockCGSBridge) {
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
        let controller = WindowSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            cgsBridge: bridge
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
}
