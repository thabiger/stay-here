import XCTest
import Core
@testable import StayHereApp

private struct FakeSnapshot: Equatable {
    let selectedID: Int?
}

private struct FakeSession: SwitcherSession {
    let startingID: Int?
    var selectedID: Int?
    let shortcut: SpaceSwitcherShortcut
    let trigger: SwitcherSessionTrigger

    var selectedItem: Int? {
        get { selectedID }
        set { selectedID = newValue }
    }

    var didChangeSelection: Bool {
        selectedID != nil && selectedID != startingID
    }
}

final class SwitcherSessionControllerTests: XCTestCase {
    private func makeController(
        movesSelectionOnNewSession: Bool = true,
        shouldCommit: @escaping (FakeSession) -> Bool = { $0.didChangeSelection },
        commitSelection: @escaping (FakeSession?, Int) -> Bool = { _, _ in true }
    ) -> (
        SwitcherSessionController<FakeSession, FakeSnapshot, Int>,
        Ref<Bool>,
        Ref<Bool>,
        Ref<[FakeSnapshot]>
    ) {
        let dismissed = Ref(false)
        let released = Ref(false)
        let presented = Ref<[FakeSnapshot]>([])

        let controller = SwitcherSessionController<FakeSession, FakeSnapshot, Int>(
            shortcutProvider: {
                SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand])
            },
            movesSelectionOnNewSession: movesSelectionOnNewSession,
            buildSession: { shortcut, trigger in
                FakeSession(startingID: 1, selectedID: 1, shortcut: shortcut, trigger: trigger)
            },
            moveSelection: { session, offset in
                session.selectedID = (session.selectedID ?? 0) + offset
            },
            buildSnapshot: { session in
                FakeSnapshot(selectedID: session?.selectedID)
            },
            itemAtPosition: { _, position in position },
            shouldCommit: shouldCommit,
            commitSelection: commitSelection,
            presentSnapshot: { snapshot, _, _, _, _, _, _, _, _ in
                presented.value.append(snapshot)
            },
            dismissPanel: { dismissed.value = true },
            releasePanel: { released.value = true }
        )

        return (controller, dismissed, released, presented)
    }

    func testOpenSwitcherCreatesSessionAndPresentsSnapshot() {
        let (controller, _, _, presented) = makeController()

        controller.openSwitcher()

        XCTAssertTrue(controller.hasActiveSession)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 1)])
    }

    func testMoveSelectionForwardMovesSelectionAndRepresents() {
        let (controller, _, _, presented) = makeController()

        controller.openSwitcher()
        controller.moveSelectionForward()

        XCTAssertEqual(controller.testSession?.selectedID, 2)
        XCTAssertEqual(presented.value, [
            FakeSnapshot(selectedID: 1),
            FakeSnapshot(selectedID: 2)
        ])
    }

    func testMoveSelectionBackwardMovesSelectionAndRepresents() {
        let (controller, _, _, presented) = makeController()

        controller.openSwitcher()
        controller.moveSelectionBackward()

        XCTAssertEqual(controller.testSession?.selectedID, 0)
        XCTAssertEqual(presented.value.last, FakeSnapshot(selectedID: 0))
    }

    func testCloseSwitcherDismissesAndClearsSession() {
        let (controller, dismissed, _, _) = makeController()

        controller.openSwitcher()
        XCTAssertTrue(controller.hasActiveSession)

        controller.closeSwitcher()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(dismissed.value)
    }

    func testStopReleasesPanelAndClearsSession() {
        let (controller, _, released, _) = makeController()

        controller.openSwitcher()
        controller.stop()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(released.value)
    }

    func testCommitSwitcherSelectionCommitsWhenShouldCommitReturnsTrue() {
        var committedID: Int?
        let (controller, _, _, _) = makeController(
            shouldCommit: { _ in true },
            commitSelection: { _, selection in
                committedID = selection
                return true
            }
        )

        controller.openSwitcher()
        controller.moveSelectionForward()
        controller.commitSwitcherSelection()

        XCTAssertEqual(committedID, 2)
    }

    func testCommitSwitcherSelectionDismissesWhenShouldCommitReturnsFalse() {
        let (controller, dismissed, _, _) = makeController(
            shouldCommit: { _ in false }
        )

        controller.openSwitcher()
        controller.commitSwitcherSelection()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(dismissed.value)
    }

    func testKeyboardShortcutDoesNotMoveOnFirstTriggerWhenConfigured() {
        let (controller, _, _, presented) = makeController(
            movesSelectionOnNewSession: false
        )

        controller.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(controller.testSession?.selectedID, 1)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 1)])
    }

    func testKeyboardShortcutMovesOnFirstTriggerWhenConfigured() {
        let (controller, _, _, presented) = makeController(
            movesSelectionOnNewSession: true
        )

        controller.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(controller.testSession?.selectedID, 2)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 2)])
    }
}

private final class Ref<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
