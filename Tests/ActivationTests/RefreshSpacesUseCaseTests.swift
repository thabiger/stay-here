import XCTest
import Core
import TestHelpers

/// A deterministic bridge that reports the `initial` snapshot for the first
/// `flipAfterCalls` `managedSnapshot()`/`activeSpaceID()` calls, then the `flipped`
/// snapshot. This makes convergence tests timing-independent.
private final class DelayedFlipMockCGSBridge: CGSBridgeProtocol {
    private var snapshotCalls = 0
    private var activeSpaceCalls = 0
    private let initialActive: Int?
    private let initialSnapshot: CGSBridge.ManagedSnapshot
    private let flippedActive: Int?
    private let flippedSnapshot: CGSBridge.ManagedSnapshot
    private let flipAfterCalls: Int

    var snapshotCallCount: Int { snapshotCalls }

    init(
        initialActive: Int?,
        initialSnapshot: CGSBridge.ManagedSnapshot,
        flippedActive: Int?,
        flippedSnapshot: CGSBridge.ManagedSnapshot,
        flipAfterCalls: Int
    ) {
        self.initialActive = initialActive
        self.initialSnapshot = initialSnapshot
        self.flippedActive = flippedActive
        self.flippedSnapshot = flippedSnapshot
        self.flipAfterCalls = flipAfterCalls
    }

    func activeSpaceID() -> Int? {
        defer { activeSpaceCalls += 1 }
        return activeSpaceCalls >= flipAfterCalls ? flippedActive : initialActive
    }

    func managedSnapshot() -> CGSBridge.ManagedSnapshot {
        defer { snapshotCalls += 1 }
        return snapshotCalls >= flipAfterCalls ? flippedSnapshot : initialSnapshot
    }

    func managedSpaces() -> [SpaceIdentity] {
        managedSnapshot().spaces
    }

    func switchByDesktopShortcut(index: Int) -> Bool {
        true
    }

    func spacesForWindow(windowID: Int) -> [Int] {
        []
    }
}

private func snapshot(
    _ id: Int,
    display: String = "display-a"
) -> CGSBridge.ManagedSnapshot {
    CGSBridge.ManagedSnapshot(
        spaces: [SpaceIdentity(id: id, display: display, kind: .desktop)],
        activeByDisplay: [display: id],
        orderedIDsByDisplay: [display: [id]]
    )
}

@MainActor
final class RefreshSpacesUseCaseTests: XCTestCase {
    func testExecuteAppliesSnapshotImmediately() {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: snapshot(201, display: "display-b")
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.refreshNow()

        XCTAssertEqual(repository.activeSpaceID, 201)
        XCTAssertEqual(repository.spaces.map(\.id), [201])
    }

    func testExecuteAsyncAppliesSnapshot() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: snapshot(201, display: "display-b")
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.refreshAsync()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(repository.activeSpaceID, 201)
    }

    func testRefreshSoonAppliesSnapshotAndFollowsExplicitRefreshes() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: snapshot(101)
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.refreshSoon()
        XCTAssertEqual(repository.activeSpaceID, 101)

        // A later space change is NOT picked up without an explicit refresh (no ambient retry loop)
        bridge.activeSpaceIDValue = 102
        bridge.managedSnapshotValue = snapshot(102)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(repository.activeSpaceID, 101)

        useCase.refreshSoon()
        XCTAssertEqual(repository.activeSpaceID, 102)
    }

    func testRefreshSoonConvergingAppliesImmediately() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: snapshot(201, display: "display-b")
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 201)
    }

    func testRefreshSoonConvergingConvergesToLatestStableActiveSpace() async {
        // The first reads are stale (101); the converging refresh must keep retrying
        // until the active space flips to 102 and reads consecutively stable.
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 101,
            initialSnapshot: snapshot(101),
            flippedActive: 102,
            flippedSnapshot: snapshot(102),
            flipAfterCalls: 3
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 102)
    }

    func testRefreshSoonConvergingWithoutExpectedIDConvergesToStableSnapshot() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 301,
            managedSnapshotValue: snapshot(301, display: "display-c")
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 301)
    }

    func testRefreshSoonConvergingRetriesUntilStable() async {
        // No expected ID: the converging refresh retries until the snapshot's active
        // space stabilizes, catching the late flip to 402.
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 401,
            initialSnapshot: snapshot(401, display: "display-d"),
            flippedActive: 402,
            flippedSnapshot: snapshot(402, display: "display-d"),
            flipAfterCalls: 2
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 402)
    }

    func testConvergingRefreshRequiresConsecutiveStableReadsBeforeAccepting() async {
        // A single agreeing pair must NOT be accepted: the first loop read agrees on
        // the stale 501 baseline, but convergence must continue until 502 has been
        // observed twice in a row.
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 501,
            initialSnapshot: snapshot(501, display: "display-e"),
            flippedActive: 502,
            flippedSnapshot: snapshot(502, display: "display-e"),
            flipAfterCalls: 3
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 502)
    }

    func testConvergingRefreshObservesDelayedFlipLandedAfterBaselineReads() async {
        // The flip lands only after 4 snapshot reads; reads 1-4 (init + immediate +
        // two loop reads) are all stale 601. The loop must NOT accept the stale
        // baseline as stable and must keep polling until the flip to 602 has been
        // observed twice in a row — all within the 8-attempt budget.
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 601,
            initialSnapshot: snapshot(601, display: "display-f"),
            flippedActive: 602,
            flippedSnapshot: snapshot(602, display: "display-f"),
            flipAfterCalls: 4
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        await task.value

        XCTAssertEqual(repository.activeSpaceID, 602)
        // 1 (init) + 1 (immediate) + 4 (loop reads; flip lands on read 5) = 6.
        // Exiting early on stale reads would stop at 4 with activeSpaceID 601.
        XCTAssertEqual(bridge.snapshotCallCount, 6)
    }

    func testConvergingRefreshCancellationInterruptsTheLoop() async {
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 901,
            initialSnapshot: snapshot(901),
            flippedActive: 902,
            flippedSnapshot: snapshot(902),
            flipAfterCalls: 100_000
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        let task = useCase.refreshSoonConverging()
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        await task.value

        // An uncancelled loop would exhaust the 8-attempt budget (~10 snapshots);
        // cancellation must stop it after at most a couple of reads.
        XCTAssertLessThan(bridge.snapshotCallCount, 6)
        XCTAssertEqual(repository.activeSpaceID, 901)
    }

    func testOverlappingConvergingCallsCoalesceToSingleLoop() async {
        let bridge = DelayedFlipMockCGSBridge(
            initialActive: 701,
            initialSnapshot: snapshot(701),
            flippedActive: 702,
            flippedSnapshot: snapshot(702),
            flipAfterCalls: 100_000
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge)
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.refreshSoonConverging()
        useCase.refreshSoonConverging()
        let last = useCase.refreshSoonConverging()
        await last.value

        XCTAssertEqual(repository.activeSpaceID, 701)
        // 1 (init) + 3 (immediate snapshots) + 8 (single loop's budget — reads never
        // leave the stale baseline, so the loop never accepts and exhausts the budget) = 12.
        // Without coalescing each cancelled loop would run its own reads (~10 each).
        XCTAssertEqual(bridge.snapshotCallCount, 12)
    }
}
