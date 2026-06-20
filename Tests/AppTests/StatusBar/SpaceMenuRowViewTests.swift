import XCTest
import AppKit
@testable import StayHereApp

@MainActor
final class SpaceMenuRowViewTests: XCTestCase {
    func testStartingEditRequiresCoordinatorApproval() {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        coordinator.allowBeginEditing = false
        let row = makeRow(spaceID: 7, name: "Alpha", coordinator: coordinator)

        row.beginEditingForTesting()

        XCTAssertEqual(coordinator.beginEditingCalls, [7])
        XCTAssertFalse(row.isEditingForTesting)
        XCTAssertTrue(row.isEditorHiddenForTesting)
        XCTAssertFalse(row.isNameFieldHiddenForTesting)
    }

    func testCommitSendsRawValueAndRestoresVisibleLabel() {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        let row = makeRow(spaceID: 3, name: "Alpha", coordinator: coordinator)

        row.beginEditingForTesting()
        row.setEditorTextForTesting("  Renamed Space  ")
        row.finishEditingForTesting(commit: true)

        XCTAssertFalse(row.isEditingForTesting)
        XCTAssertTrue(row.isEditorHiddenForTesting)
        XCTAssertFalse(row.isNameFieldHiddenForTesting)
        XCTAssertEqual(row.displayedNameForTesting, "  Renamed Space  ")
        XCTAssertEqual(coordinator.finishEditingCalls.count, 1)
        XCTAssertEqual(coordinator.finishEditingCalls.first?.spaceID, 3)
        XCTAssertEqual(coordinator.finishEditingCalls.first?.name, "  Renamed Space  ")
        XCTAssertEqual(coordinator.finishEditingCalls.first?.commit, true)
    }

    func testWhitespaceNameFallsBackToUnnamedSpaceLocally() {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        let row = makeRow(spaceID: 11, name: "Alpha", coordinator: coordinator)

        row.beginEditingForTesting()
        row.setEditorTextForTesting("   ")
        row.finishEditingForTesting(commit: true)

        XCTAssertEqual(row.displayedNameForTesting, "Unnamed space")
        XCTAssertEqual(coordinator.finishEditingCalls.first?.name, "   ")
    }

    func testBeginningSecondRowCommitsPreviousActiveRow() {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        let firstRow = makeRow(spaceID: 1, name: "One", coordinator: coordinator)
        let secondRow = makeRow(spaceID: 2, name: "Two", coordinator: coordinator)

        firstRow.beginEditingForTesting()
        firstRow.setEditorTextForTesting("First renamed")
        secondRow.beginEditingForTesting()

        XCTAssertEqual(coordinator.beginEditingCalls, [1, 2])
        XCTAssertEqual(coordinator.finishEditingCalls.count, 1)
        XCTAssertEqual(coordinator.finishEditingCalls.first?.spaceID, 1)
        XCTAssertEqual(coordinator.finishEditingCalls.first?.name, "First renamed")
        XCTAssertFalse(firstRow.isEditingForTesting)
        XCTAssertTrue(secondRow.isEditingForTesting)
    }

    func testTextChangeReschedulesAutoCommitTimer() throws {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        let row = makeRow(spaceID: 5, name: "Alpha", coordinator: coordinator)

        row.beginEditingForTesting()
        let initialTimer = try XCTUnwrap(row.autoCommitTimerForTesting)

        row.controlTextDidChange(Notification(name: NSText.didChangeNotification))

        let rescheduledTimer = try XCTUnwrap(row.autoCommitTimerForTesting)
        XCTAssertFalse(initialTimer.isValid)
        XCTAssertTrue(rescheduledTimer.isValid)
        XCTAssertFalse(initialTimer === rescheduledTimer)
    }

    func testFinishingEditInvalidatesTimers() throws {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        let row = makeRow(spaceID: 9, name: "Alpha", coordinator: coordinator)

        row.beginEditingForTesting()
        let autoCommitTimer = try XCTUnwrap(row.autoCommitTimerForTesting)
        let focusRepairTimer = try XCTUnwrap(row.focusRepairTimerForTesting)

        row.finishEditingForTesting(commit: false)

        XCTAssertNil(row.autoCommitTimerForTesting)
        XCTAssertNil(row.focusRepairTimerForTesting)
        XCTAssertFalse(autoCommitTimer.isValid)
        XCTAssertFalse(focusRepairTimer.isValid)
    }

    func testDeinitInvalidatesTimers() throws {
        let coordinator = SpaceMenuRowCoordinatorSpy()
        weak var weakRow: SpaceMenuRowView?
        var autoCommitTimer: Timer?
        var focusRepairTimer: Timer?

        autoreleasepool {
            let row = makeRow(spaceID: 13, name: "Alpha", coordinator: coordinator)
            weakRow = row
            row.beginEditingForTesting()
            autoCommitTimer = try? XCTUnwrap(row.autoCommitTimerForTesting)
            focusRepairTimer = try? XCTUnwrap(row.focusRepairTimerForTesting)
        }

        XCTAssertNil(weakRow)
        let unwrappedAutoCommitTimer = try XCTUnwrap(autoCommitTimer)
        let unwrappedFocusRepairTimer = try XCTUnwrap(focusRepairTimer)
        
        XCTAssertFalse(unwrappedAutoCommitTimer.isValid)
        XCTAssertFalse(unwrappedFocusRepairTimer.isValid)
    }

    private func makeRow(spaceID: Int, name: String, coordinator: SpaceMenuRowCoordinatorSpy) -> SpaceMenuRowView {
        SpaceMenuRowView(
            spaceID: spaceID,
            namespaceLabel: "Work",
            name: name,
            controller: coordinator
        )
    }
}

@MainActor
private final class SpaceMenuRowCoordinatorSpy: SpaceMenuRowViewCoordinating {
    struct FinishCall {
        let spaceID: Int
        let name: String
        let commit: Bool
    }

    var isEditingSpaceName = false
    var currentAppearance: NSAppearance?
    var allowBeginEditing = true
    private(set) var beginEditingCalls: [Int] = []
    private(set) var finishEditingCalls: [FinishCall] = []
    private weak var activeRow: SpaceMenuRowView?
    private var activeSpaceID: Int?

    func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool {
        beginEditingCalls.append(spaceID)
        guard allowBeginEditing else { return false }
        if let activeRow, activeSpaceID != spaceID {
            activeRow.commitEditFromController()
        }
        guard !isEditingSpaceName || activeSpaceID == spaceID else { return false }
        activeRow = row
        activeSpaceID = spaceID
        isEditingSpaceName = true
        return true
    }

    func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool) {
        finishEditingCalls.append(FinishCall(spaceID: spaceID, name: name, commit: commit))
        if activeRow === row {
            activeRow = nil
            activeSpaceID = nil
            isEditingSpaceName = false
        }
    }

    func selectSpace(_ spaceID: Int) {}

    func commitActiveEdit() {
        activeRow?.commitEditFromController()
    }
}
