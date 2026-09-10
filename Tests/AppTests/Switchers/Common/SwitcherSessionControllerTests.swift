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

private final class MockSwitcherSessionDelegate: SwitcherSessionDelegate {
    typealias Session = FakeSession
    typealias Snapshot = FakeSnapshot
    typealias Selection = Int

    var movesSelectionOnNewSession: Bool = true
    var provideShortcutImpl: () -> SpaceSwitcherShortcut = {
        SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand])
    }
    var buildSessionImpl: (SpaceSwitcherShortcut, SwitcherSessionTrigger) -> FakeSession? = { shortcut, trigger in
        FakeSession(startingID: 1, selectedID: 1, shortcut: shortcut, trigger: trigger)
    }
    var moveSelectionImpl: (inout FakeSession, Int) -> Void = { session, offset in
        session.selectedID = (session.selectedID ?? 0) + offset
    }
    var buildSnapshotImpl: (FakeSession?) -> FakeSnapshot = { FakeSnapshot(selectedID: $0?.selectedID) }
    var itemAtPositionImpl: (FakeSession?, Int) -> Int? = { _, position in position }
    var shouldCommitImpl: (FakeSession) -> Bool = { $0.didChangeSelection }
    var commitSelectionImpl: (FakeSession?, Int) -> Bool = { _, _ in true }

    func provideShortcut() -> SpaceSwitcherShortcut { provideShortcutImpl() }
    func buildSession(shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> FakeSession? { buildSessionImpl(shortcut, trigger) }
    func moveSelection(in session: inout FakeSession, offset: Int) { moveSelectionImpl(&session, offset) }
    func buildSnapshot(for session: FakeSession?) -> FakeSnapshot { buildSnapshotImpl(session) }
    func item(at position: Int, in session: FakeSession?) -> Int? { itemAtPositionImpl(session, position) }
    func shouldCommit(_ session: FakeSession) -> Bool { shouldCommitImpl(session) }
    func commit(selection: Int, in session: FakeSession?) -> Bool { commitSelectionImpl(session, selection) }
}

private final class MockSwitcherPanelPresenter: SwitcherPanelPresenting {
    typealias Snapshot = FakeSnapshot
    typealias Selection = Int

    var presented: [FakeSnapshot] = []
    var dismissed = false
    var released = false

    func presentSnapshot(_ snapshot: FakeSnapshot, actions: SwitcherPanelActions<Int>, updateInfo: UpdateInfo?) {
        presented.append(snapshot)
    }

    func dismissPanel() { dismissed = true }

    func releasePanel() { released = true }
}

@MainActor
final class SwitcherSessionControllerTests: XCTestCase {
    private var delegate: MockSwitcherSessionDelegate!
    private var presenter: MockSwitcherPanelPresenter!

    private func makeController(
        movesSelectionOnNewSession: Bool = true,
        shouldCommitImpl: @escaping (FakeSession) -> Bool = { $0.didChangeSelection },
        commitSelectionImpl: @escaping (FakeSession?, Int) -> Bool = { _, _ in true }
    ) -> SwitcherSessionController<FakeSession, FakeSnapshot, Int> {
        delegate = MockSwitcherSessionDelegate()
        delegate.movesSelectionOnNewSession = movesSelectionOnNewSession
        delegate.shouldCommitImpl = shouldCommitImpl
        delegate.commitSelectionImpl = commitSelectionImpl

        presenter = MockSwitcherPanelPresenter()
        let controller = SwitcherSessionController(delegate: delegate, panelPresenter: presenter)

        return controller
    }

    func testOpenSwitcherCreatesSessionAndPresentsSnapshot() {
        let controller = makeController()

        controller.openSwitcher()

        XCTAssertTrue(controller.hasActiveSession)
        XCTAssertEqual(presenter.presented, [FakeSnapshot(selectedID: 1)])
    }

    func testMoveSelectionForwardMovesSelectionAndRepresents() {
        let controller = makeController()

        controller.openSwitcher()
        controller.moveSelectionForward()

        XCTAssertEqual(controller.activeSession?.selectedID, 2)
        XCTAssertEqual(presenter.presented, [
            FakeSnapshot(selectedID: 1),
            FakeSnapshot(selectedID: 2)
        ])
    }

    func testMoveSelectionBackwardMovesSelectionAndRepresents() {
        let controller = makeController()

        controller.openSwitcher()
        controller.moveSelectionBackward()

        XCTAssertEqual(controller.activeSession?.selectedID, 0)
        XCTAssertEqual(presenter.presented.last, FakeSnapshot(selectedID: 0))
    }

    func testCloseSwitcherDismissesAndClearsSession() {
        let controller = makeController()

        controller.openSwitcher()
        XCTAssertTrue(controller.hasActiveSession)

        controller.closeSwitcher()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(presenter.dismissed)
    }

    func testStopReleasesPanelAndClearsSession() {
        let controller = makeController()

        controller.openSwitcher()
        controller.stop()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(presenter.released)
    }

    func testCommitSwitcherSelectionCommitsWhenShouldCommitReturnsTrue() {
        var committedID: Int?
        let controller = makeController(
            shouldCommitImpl: { _ in true },
            commitSelectionImpl: { _, selection in
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
        let controller = makeController(
            shouldCommitImpl: { _ in false }
        )

        controller.openSwitcher()
        controller.commitSwitcherSelection()

        XCTAssertFalse(controller.hasActiveSession)
        XCTAssertTrue(presenter.dismissed)
    }

    func testKeyboardShortcutDoesNotMoveOnFirstTriggerWhenConfigured() {
        let controller = makeController(
            movesSelectionOnNewSession: false
        )

        controller.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(controller.activeSession?.selectedID, 1)
        XCTAssertEqual(presenter.presented, [FakeSnapshot(selectedID: 1)])
    }

    func testKeyboardShortcutMovesOnFirstTriggerWhenConfigured() {
        let controller = makeController(
            movesSelectionOnNewSession: true
        )

        controller.switcherEnsureSessionAndMoveSelection(backward: false)

        XCTAssertEqual(controller.activeSession?.selectedID, 2)
        XCTAssertEqual(presenter.presented, [FakeSnapshot(selectedID: 2)])
    }

    func testReplaceActiveSessionRepresentsUpdatedSnapshot() {
        let controller = makeController()

        controller.openSwitcher()
        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertTrue(controller.hasActiveSession)

        // Replace with a new session that has a different selectedID
        delegate.buildSessionImpl = { shortcut, trigger in
            FakeSession(startingID: 1, selectedID: 5, shortcut: shortcut, trigger: trigger)
        }
        let newSession = FakeSession(startingID: 1, selectedID: 5, shortcut: SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand]), trigger: .explicit)
        controller.replaceActiveSession(with: newSession)

        XCTAssertEqual(controller.activeSession?.selectedID, 5)
        XCTAssertTrue(controller.hasActiveSession, "hasActiveSession should stay true after replace")
        XCTAssertEqual(presenter.presented.last, FakeSnapshot(selectedID: 5), "Panel should be re-presented with updated snapshot")
    }

    func testReplaceActiveSessionIsNoopWithoutActiveSession() {
        let controller = makeController()

        let initialPresentedCount = presenter.presented.count

        // Replace with no active session — should be a no-op
        let newSession = FakeSession(startingID: 1, selectedID: 5, shortcut: SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand]), trigger: .explicit)
        controller.replaceActiveSession(with: newSession)

        XCTAssertEqual(presenter.presented.count, initialPresentedCount, "No new presentation when there is no active session")
        XCTAssertFalse(controller.hasActiveSession)
    }
}
