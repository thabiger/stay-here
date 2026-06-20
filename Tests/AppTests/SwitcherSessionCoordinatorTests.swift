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

final class SwitcherSessionCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        movesSelectionOnNewSession: Bool = true,
        shouldCommit: @escaping (FakeSession) -> Bool = { $0.didChangeSelection },
        commitSelection: @escaping (FakeSession?, Int) -> Bool = { _, _ in true }
    ) -> (
        SwitcherSessionCoordinator<FakeSession, FakeSnapshot, Int>,
        Ref<Bool>,
        Ref<Bool>,
        Ref<[FakeSnapshot]>
    ) {
        let dismissed = Ref(false)
        let released = Ref(false)
        let presented = Ref<[FakeSnapshot]>([])

        let coordinator = SwitcherSessionCoordinator<FakeSession, FakeSnapshot, Int>(
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

        return (coordinator, dismissed, released, presented)
    }

    func testOpenSwitcherCreatesSessionAndPresentsSnapshot() {
        let (coordinator, _, _, presented) = makeCoordinator()

        coordinator.openSwitcher()

        XCTAssertTrue(coordinator.hasActiveSession)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 1)])
    }

    func testMoveSelectionForwardMovesSelectionAndRepresents() {
        let (coordinator, _, _, presented) = makeCoordinator()

        coordinator.openSwitcher()
        coordinator.moveSelectionForward()

        XCTAssertEqual(coordinator.testSession?.selectedID, 2)
        XCTAssertEqual(presented.value, [
            FakeSnapshot(selectedID: 1),
            FakeSnapshot(selectedID: 2)
        ])
    }

    func testMoveSelectionBackwardMovesSelectionAndRepresents() {
        let (coordinator, _, _, presented) = makeCoordinator()

        coordinator.openSwitcher()
        coordinator.moveSelectionBackward()

        XCTAssertEqual(coordinator.testSession?.selectedID, 0)
        XCTAssertEqual(presented.value.last, FakeSnapshot(selectedID: 0))
    }

    func testCloseSwitcherDismissesAndClearsSession() {
        let (coordinator, dismissed, _, _) = makeCoordinator()

        coordinator.openSwitcher()
        XCTAssertTrue(coordinator.hasActiveSession)

        coordinator.closeSwitcher()

        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertTrue(dismissed.value)
    }

    func testStopReleasesPanelAndClearsSession() {
        let (coordinator, _, released, _) = makeCoordinator()

        coordinator.openSwitcher()
        coordinator.stop()

        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertTrue(released.value)
    }

    func testCommitSwitcherSelectionCommitsWhenShouldCommitReturnsTrue() {
        var committedID: Int?
        let (coordinator, _, _, _) = makeCoordinator(
            shouldCommit: { _ in true },
            commitSelection: { _, selection in
                committedID = selection
                return true
            }
        )

        coordinator.openSwitcher()
        coordinator.moveSelectionForward()
        coordinator.commitSwitcherSelection()

        XCTAssertEqual(committedID, 2)
    }

    func testCommitSwitcherSelectionDismissesWhenShouldCommitReturnsFalse() {
        let (coordinator, dismissed, _, _) = makeCoordinator(
            shouldCommit: { _ in false }
        )

        coordinator.openSwitcher()
        coordinator.commitSwitcherSelection()

        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertTrue(dismissed.value)
    }

    func testKeyboardShortcutDoesNotMoveOnFirstTriggerWhenConfigured() {
        let (coordinator, _, _, presented) = makeCoordinator(
            movesSelectionOnNewSession: false
        )

        coordinator.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(coordinator.testSession?.selectedID, 1)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 1)])
    }

    func testKeyboardShortcutMovesOnFirstTriggerWhenConfigured() {
        let (coordinator, _, _, presented) = makeCoordinator(
            movesSelectionOnNewSession: true
        )

        coordinator.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(coordinator.testSession?.selectedID, 2)
        XCTAssertEqual(presented.value, [FakeSnapshot(selectedID: 2)])
    }
}

private final class Ref<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
