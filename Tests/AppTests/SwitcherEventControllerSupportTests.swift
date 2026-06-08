import Core
import CoreGraphics
import XCTest
@testable import StayHereApp

private final class FakeSwitcherHandler: SwitcherEventSessionHandling {
    var shortcut = SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
    var hasActiveSessionValue = false
    var sessionModifiersValue: CGEventFlags?
    var moveSelections: [Bool] = []
    var commitOrDismissCount = 0
    var cancelCount = 0

    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut { shortcut }
    func switcherHasActiveSession() -> Bool { hasActiveSessionValue }
    func switcherSessionModifiers() -> CGEventFlags? { sessionModifiersValue }
    func switcherEnsureSessionAndMoveSelection(backward: Bool) { moveSelections.append(backward) }
    func switcherCommitOrDismissActiveSession() { commitOrDismissCount += 1 }
    func switcherCancelActiveSession() { cancelCount += 1 }
}

final class SwitcherEventControllerSupportTests: XCTestCase {
    private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return event
    }

    private func waitForMainQueue(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "main-queue-drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    func testTapDisabledEventReEnablesExistingTap() {
        let handler = FakeSwitcherHandler()
        var enableCalls: [Bool] = []
        let support = SwitcherEventControllerSupport(
            handler: handler,
            eventTapUnavailableLog: "test",
            eventTapFactory: { _, _ in nil },
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in }
        )

        support.handleTapDisabledEvent(forceReenable: true)

        XCTAssertEqual(enableCalls, [true])
    }

    func testNonMatchingKeyCancelsActiveSession() {
        let handler = FakeSwitcherHandler()
        handler.hasActiveSessionValue = true
        let support = SwitcherEventControllerSupport(handler: handler, eventTapUnavailableLog: "test")

        let result = support.handleKeyDown(event: makeKeyEvent(keyCode: 12, flags: .maskCommand))
        waitForMainQueue()

        XCTAssertNil(result)
        XCTAssertEqual(handler.cancelCount, 1)
    }

    func testNonMatchingKeyPassesThroughWhenIdle() {
        let handler = FakeSwitcherHandler()
        let support = SwitcherEventControllerSupport(handler: handler, eventTapUnavailableLog: "test")
        let event = makeKeyEvent(keyCode: 12, flags: .maskCommand)

        let result = support.handleKeyDown(event: event)?.takeUnretainedValue()

        XCTAssertNotNil(result)
        XCTAssertEqual(handler.cancelCount, 0)
    }

    func testModifierReleaseDispatchesCommitOrDismiss() {
        let handler = FakeSwitcherHandler()
        handler.sessionModifiersValue = [.maskCommand]
        let support = SwitcherEventControllerSupport(handler: handler, eventTapUnavailableLog: "test")

        _ = support.handleFlagsChanged(event: makeKeyEvent(keyCode: 50, flags: []))
        waitForMainQueue()

        XCTAssertEqual(handler.commitOrDismissCount, 1)
    }

    func testMatchingShortcutMovesBackwardWhenShiftIsAdded() {
        let handler = FakeSwitcherHandler()
        let support = SwitcherEventControllerSupport(handler: handler, eventTapUnavailableLog: "test")

        _ = support.handleKeyDown(event: makeKeyEvent(keyCode: 50, flags: [.maskCommand, .maskShift]))
        waitForMainQueue()

        XCTAssertEqual(handler.moveSelections, [true])
    }
}
