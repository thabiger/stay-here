import XCTest
import Core
import TestHelpers

@MainActor
final class SpaceStateManagerTests: XCTestCase {
    func testRefreshSpacesUsesInjectedBridgeSnapshot() {
        let store = makeStore()
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .fullscreen)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201]]
        )
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: snapshot
        )

        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)

        XCTAssertEqual(repository.activeSpaceID, 201)
        XCTAssertEqual(repository.spaces.map(\.id), [201, 202])
        XCTAssertEqual(repository.desktopNumberBySpaceID[101], 1)
        XCTAssertEqual(repository.desktopNumberBySpaceID[102], 2)
        XCTAssertEqual(repository.desktopNumberBySpaceID[201], 1)
    }

    func testSwitchToSpaceUsesInjectedBridgeShortcutPosting() async {
        let store = makeStore()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
        )
        var postedIndex: Int?
        bridge.switchByDesktopShortcutHandler = { index in
            postedIndex = index
            bridge.activeSpaceIDValue = 102
            bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 102],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
            return true
        }

        let pair = SpaceStateManagerFactory.makePair(cgsBridge: bridge, store: store)
        let refreshSpaces = RefreshSpacesUseCase(repository: pair.manager, logger: NoOpLogger())
        let switchSpace = SwitchSpaceUseCase(
            cgsBridge: bridge,
            repository: pair.queryService,
            refreshUseCase: refreshSpaces,
            logger: NoOpLogger()
        )
        let result = await switchSpace.execute(102)

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
        XCTAssertEqual(pair.manager.activeSpaceID, 102)
    }

    func testRenamePersistsAcrossRepositoryInstances() {
        let store = makeStore()
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )

        let writerPair = SpaceStateManagerFactory.makePair(
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            store: store
        )
        writerPair.manager.rename(spaceID: 101, name: "Inbox")
        writerPair.manager.persistNow()

        let readerPair = SpaceStateManagerFactory.makePair(
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            store: store
        )

        XCTAssertEqual(readerPair.queryService.name(for: 101), "Inbox")
    }

    func testInitDoesNotDropPersistedLabelsWhenSnapshotIsTransientlyEmpty() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let pair = SpaceStateManagerFactory.makePair(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: nil,
                managedSnapshotValue: .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
            ),
            store: store
        )

        XCTAssertTrue(pair.manager.isStaleSnapshot)
        XCTAssertEqual(pair.queryService.name(for: 101), "Inbox")
        XCTAssertNil(pair.manager.labels[1], "Stale snapshots must not fabricate a label for space 1")

        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[101]?.name, "Inbox")
        XCTAssertNil(reloaded.labels[1])
    }

    func testRefreshAfterTransientEmptySnapshotKeepsLabelsForRecoveredSpaces() {
        let store = makeStore()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: nil,
            managedSnapshotValue: .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
        )
        try? store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let pair = SpaceStateManagerFactory.makePair(cgsBridge: bridge, store: store)
        XCTAssertTrue(pair.manager.isStaleSnapshot)

        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )
        pair.manager.refreshSpaces()

        XCTAssertFalse(pair.manager.isStaleSnapshot)
        XCTAssertEqual(pair.queryService.name(for: 101), "Inbox")
        XCTAssertEqual(pair.manager.spaces.map(\.id), [101])
    }

    func testRefreshWithNonEmptySnapshotAndEmptyDiscoveredDoesNotWipeLabels() {
        let store = makeStore()
        try? store.save(PersistedSpaces(labels: [101: SpaceLabel(name: "Inbox")]))

        // Phase 1: good state — spaces on display-a, selected display has spaces.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
        )
        let pair = SpaceStateManagerFactory.makePair(cgsBridge: bridge, store: store)
        XCTAssertEqual(pair.manager.spaces.map(\.id), [101, 102])

        // Phase 2: transient bad state — spaces only on display-b, focus on display-a → discovered empty.
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        pair.manager.refreshSpaces()

        XCTAssertEqual(pair.manager.spaces.map(\.id), [101, 102],
                       "Previous spaces must be retained, not replaced by an empty list")
        XCTAssertEqual(pair.queryService.name(for: 101), "Inbox")
        XCTAssertNil(pair.manager.labels[1], "Space 1 must not gain a label during retention")
        XCTAssertNil(pair.manager.labels[201],
                     "ARCH-4: retained/untrusted snapshots must not fabricate labels; the label appears on the next trusted observation of that space")

        pair.manager.persistNow()   // flush any pending debounced write before reload
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[101]?.name, "Inbox")
        XCTAssertNil(reloaded.labels[1])
        XCTAssertNil(reloaded.labels[201])
    }

    func testMultiDisplayFocusCrossingDoesNotWipeLabelsOnOtherDisplay() {
        let store = makeStore()
        try? store.save(PersistedSpaces(labels: [201: SpaceLabel(name: "Work")]))

        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201, 202]]
        )
        let bridge = MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot)

        // Phase 1 — launch with focus on display-a: display-b label must survive the init observation.
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102],
                       "Derived spaces stay display-filtered; only the observation universe widens")
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Launch observation must not drop labels of the non-focused display")

        // Phase 2 — focus crosses to display-b.
        bridge.activeSpaceIDValue = 201
        repository.refreshSpaces()
        XCTAssertEqual(repository.spaces.map(\.id), [201, 202])
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Focus-crossing observation must not drop labels of the other display")

        // Phase 3 — focus crosses back to display-a.
        bridge.activeSpaceIDValue = 101
        repository.refreshSpaces()
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102])
        XCTAssertEqual(repository.labels[201]?.name, "Work")

        repository.persistNow() // flush any pending debounced write before reload
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[201]?.name, "Work",
                       "spaces.json must keep the display-b label across focus crossings")
    }

    func testRefreshWithTransientlyPartialSnapshotDoesNotWipeLabelsOnMissingDisplay() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [201: SpaceLabel(name: "Work")],
                spaceDisplayByID: [201: "display-b"]
            )
        )

        // Phase 1: complete two-display snapshot; display-b label must survive the init observation.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                    SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101, "display-b": 201],
                orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201, 202]]
            )
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
        XCTAssertEqual(repository.labels[201]?.name, "Work")
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102])

        // Phase 2: transiently-partial snapshot — display-b missing entirely.
        bridge.activeSpaceIDValue = 103
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 103],
            orderedIDsByDisplay: ["display-a": [101, 102, 103]]
        )
        repository.refreshSpaces()

        XCTAssertEqual(repository.spaces.map(\.id), [101, 102, 103],
                       "The partial snapshot is a genuine change and is adopted")
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Label on the unobserved display must survive in memory")

        repository.persistNow()   // flush any pending debounced write before reload
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[201]?.name, "Work",
                       "Label on the unobserved display must survive on disk")
        XCTAssertEqual(reloaded.spaceDisplayByID[201], "display-b")

        // Phase 3: recovery — display-b returns with the label intact.
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 103, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102, 103], "display-b": [201, 202]]
        )
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Label must survive once display-b is observed again")
    }

    func testInitDoesNotWipePersistedLabelsWhenFirstSnapshotIsTransientlyPartial() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [201: SpaceLabel(name: "Work")],
                spaceDisplayByID: [201: "display-b"]
            )
        )

        // First snapshot is transiently partial: display-b is missing at launch.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)

        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Launch observation must not prune labels of the unobserved display")
        XCTAssertEqual(repository.labels[101]?.name, "Unnamed space")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[201]?.name, "Work",
                       "Disk must retain the label after a partial launch snapshot")
        XCTAssertEqual(reloaded.spaceDisplayByID[201], "display-b")

        // Recovery: display-b returns with the label intact.
        bridge.activeSpaceIDValue = 201
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101], "display-b": [201]]
        )
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Label must survive the recovery snapshot")
    }

    func testInitDoesNotWipeLegacyLabelsWithoutDisplayMapWhenFirstSnapshotIsTransientlyPartial() {
        let store = makeStore()
        try? store.save(PersistedSpaces(labels: [201: SpaceLabel(name: "Work")]))

        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)

        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Legacy labels without a display association cannot be positively confirmed as removed")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[201]?.name, "Work",
                       "Disk must retain the legacy label")
        XCTAssertNil(reloaded.spaceDisplayByID[201])
    }

    func testCompleteSnapshotStillPrunesGenuinelyRemovedSpace() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [201: SpaceLabel(name: "Work")],
                spaceDisplayByID: [201: "display-b"]
            )
        )

        // Launch with a complete snapshot including 201.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                    SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101, "display-b": 201],
                orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201, 202]]
            )
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[201]?.name, "Work")

        // 201 genuinely removed while display-b stays observed (202 remains on it). The
        // observation-cadence budget converges even though the snapshot stops changing:
        // the label survives the first four absence observations and is pruned on the
        // fifth (0.5 s per observation → the 2.0 s floor is met).
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 103, "display-b": 202],
            orderedIDsByDisplay: ["display-a": [101, 102, 103], "display-b": [202]]
        )
        for absence in 1...4 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
            XCTAssertEqual(repository.labels[201]?.name, "Work",
                           "Absence \(absence): within the budget")
            XCTAssertEqual(repository.labels[202]?.name, "Unnamed space")
        }

        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertNil(repository.labels[201],
                     "A genuinely removed space on an observed display is pruned once the budget is exhausted")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertNil(reloaded.records[201])
        XCTAssertNil(reloaded.spaceDisplayByID[201])
    }

    func testWithinDisplayPartialSnapshotDoesNotWipeLabelOnSingleObservation() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [102: SpaceLabel(name: "Inbox")],
                spaceDisplayByID: [102: "display-a"]
            )
        )

        // Launch with a complete single-display snapshot.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: makeSnapshot(ids: [101, 102], active: 101)
        )
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // Within-display partial snapshot: display-a enumerated, but 102 omitted while
        // 103 is added. One partial observation must not wipe the label.
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103], active: 101)
        repository.refreshSpaces()

        XCTAssertEqual(repository.labels[102]?.name, "Inbox",
                       "One within-display partial observation must not wipe the label")
        XCTAssertEqual(repository.labels[103]?.name, "Unnamed space")

        repository.persistNow()   // flush any pending debounced write before reload
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[102]?.name, "Inbox",
                       "Disk must retain the label after one partial observation")

        // Recovery: 102 reappears before the budget is exhausted → label preserved.
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 102, 103], active: 101)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")
    }

    func testVanishedSpacePrunedOnlyAfterBudgetAndReappearanceResets() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [102: SpaceLabel(name: "Inbox")],
                spaceDisplayByID: [102: "display-a"]
            )
        )

        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: makeSnapshot(ids: [101, 102], active: 101)
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // 102 vanishes on the observed display: the absence budget accumulates per observation.
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103], active: 101)
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox", "Absence 1: within the budget")

        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103, 104], active: 101)
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox", "Absence 2: within the budget")

        // Reappears before the budget is exhausted → the absence count resets.
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 102, 103, 104], active: 101)
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // Vanishes again: the budget restarts from zero; pruned only after the full
        // budget (5 observations AND the 2.0 s floor) of absences on the observed display.
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103, 104, 105], active: 101)
        for absence in 1...4 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
            XCTAssertEqual(repository.labels[102]?.name, "Inbox", "Post-reset absence \(absence)")
        }

        // Fifth absence on a stable snapshot (same display set as the previous
        // observation — no growing display to skip the count) → pruned.
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertNil(repository.labels[102],
                     "Absent for the full budget of observations on an observed display → pruned")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertNil(reloaded.records[102])
        XCTAssertNil(reloaded.spaceDisplayByID[102])
    }

    func testSpaceAppearingOnNonFocusedDisplayGainsLabelAssociationAndPrunesAfterBudget() {
        let store = makeStore()
        let clock = TestClock()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: makeSnapshot(ids: [101, 102], active: 101)
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102])
        XCTAssertNil(repository.labels[201])

        // Space 201 appears on display-b while focus stays on display-a. The
        // observation cadence runs on the applied snapshot: 201 gains a default label
        // and a display association while the retained display's labels are protected.
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201]]
        )
        clock.advance(by: 0.5)
        repository.refreshSpaces()

        XCTAssertEqual(repository.spaces.map(\.id), [101, 102],
                       "Derived state stays focused on display-a")
        XCTAssertEqual(repository.labels[201]?.name, "Unnamed space",
                       "The appeared space gets a default label")
        XCTAssertNil(repository.labels[1])

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertEqual(reloaded.spaceDisplayByID[201], "display-b",
                       "The association for the appeared space is recorded")

        // 201 vanishes while display-b is still observed (202 remains on it): pruned
        // once the absence budget on the observed display is exhausted.
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 202],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [202]]
        )
        for absence in 1...4 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
            XCTAssertEqual(repository.labels[201]?.name, "Unnamed space",
                           "Absence \(absence): within the budget")
        }

        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertNil(repository.labels[201],
                     "Vanished on an observed display after the budget → pruned")

        repository.persistNow()
        let pruned = store.load()
        XCTAssertNil(pruned.records[201])
        XCTAssertNil(pruned.spaceDisplayByID[201])
    }

    func testSpaceReappearingOnDifferentDisplayResetsAbsenceCount() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [102: SpaceLabel(name: "Inbox")],
                spaceDisplayByID: [102: "display-a"]
            )
        )

        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: makeSnapshot(ids: [101, 102], active: 101)
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // Two absences on the recorded display-a (each refresh is an observation).
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103], active: 101)
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 103, 104], active: 101)
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox", "Two absences are within the budget")

        // Reappears on a DIFFERENT display (display-b): association updates, count resets.
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 104, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 102],
            orderedIDsByDisplay: ["display-a": [101, 103, 104], "display-b": [102]]
        )
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertEqual(reloaded.spaceDisplayByID[102], "display-b",
                       "The association is updated to the new display on presence")

        // Absent from display-b while display-b stays observed: the count restarts from
        // zero, so the first post-reset absences still survive (had the reset not
        // happened, the pre-existing count would already have been close to the budget).
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 104, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 202],
            orderedIDsByDisplay: ["display-a": [101, 103, 104], "display-b": [202]]
        )
        for absence in 1...2 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
            XCTAssertEqual(repository.labels[102]?.name, "Inbox", "Post-reset absence \(absence)")
        }

        // Full post-reset budget (5 observations + 2.0 s floor) → pruned.
        for _ in 1...3 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
        }
        XCTAssertNil(repository.labels[102],
                     "Five post-reset absences on the observed recorded display → pruned")
    }

    func testSlowMissionControlTransitionDoesNotWipeLabel() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [102: SpaceLabel(name: "Inbox")],
                spaceDisplayByID: [102: "display-a"]
            )
        )

        // Launch complete [101, 102] on display-a.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: makeSnapshot(ids: [101, 102], active: 101)
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // Slow Mission Control transition: 102 absent on the observed display-a while
        // the universe churns, at the real 0.2 s poll cadence. Seven observations push
        // the count past the observation budget (5) but only ~1.2 s elapse — far under
        // the 2.0 s wall-clock floor → the label must survive.
        for step in 1...7 {
            clock.advance(by: 0.2)
            bridge.managedSnapshotValue = makeSnapshot(ids: [101, 300 + step], active: 101)
            repository.refreshSpaces()
        }
        XCTAssertEqual(repository.labels[102]?.name, "Inbox",
                       "Count exceeds the observation budget but the wall-clock floor is unmet")

        repository.persistNow()
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[102]?.name, "Inbox",
                       "Disk must retain the label through the slow transition")
        XCTAssertEqual(reloaded.spaceDisplayByID[102], "display-a")

        // 102 returns → survives and the absence evidence resets.
        clock.advance(by: 0.2)
        bridge.managedSnapshotValue = makeSnapshot(ids: [101, 102], active: 101)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox",
                       "Returning space resets its absence evidence")
    }

    func testUnobservedDisplayGapResetsAbsenceBudget() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [102: SpaceLabel(name: "Inbox")],
                spaceDisplayByID: [102: "display-a"]
            )
        )

        // Launch with 102 present on display-a.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[102]?.name, "Inbox")

        // Two absence observations on the observed display-a: count = 2.
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        clock.advance(by: 0.5)
        repository.refreshSpaces()

        // Focus crosses to display-b and the snapshot observes ONLY display-b (adopted):
        // 102's recorded display-a is unobserved → its absence evidence resets. Without
        // the reset, the pre-gap count of 2 would have completed the budget quickly.
        bridge.activeSpaceIDValue = 301
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 301, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-b": 301],
            orderedIDsByDisplay: ["display-b": [301]]
        )
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox",
                       "The display-level gap resets the absence evidence")

        // Focus back on display-a, 102 still absent: the count restarts at 1, not 3.
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )
        clock.advance(by: 0.5)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[102]?.name, "Inbox",
                       "Post-gap count restarts from zero — survives")

        // Full post-gap budget with the floor met → genuine removal converges.
        for _ in 1...4 {
            clock.advance(by: 0.5)
            repository.refreshSpaces()
        }
        XCTAssertNil(repository.labels[102],
                     "Once the budget converges on the observed display the label prunes")
    }

    func testTransientlyPartialSnapshotAdoptedDoesNotWipeLabelsMidRunOrAtLaunch() {
        let store = makeStore()
        let clock = TestClock()
        try? store.save(
            PersistedSpaces(
                labels: [201: SpaceLabel(name: "Work")],
                spaceDisplayByID: [201: "display-b"]
            )
        )

        // Launch into a transiently-partial snapshot (display-a only, adopted): the
        // label of the unobserved display must survive in memory and on disk.
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let repository = SpaceStateManagerFactory.make(
            cgsBridge: bridge,
            store: store,
            now: clock.provider
        )
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Launch partial must not prune the unobserved display's label")

        repository.persistNow()
        let afterLaunch = store.load()
        XCTAssertEqual(afterLaunch.labels[201]?.name, "Work",
                       "Disk must retain the label after the partial launch snapshot")

        // Mid-run partial snapshots (display-a present, display-b absent, adopted) ×3
        // at 0.1 s steps — well under the wall-clock floor: still "Work".
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101, 102]]
        )
        for _ in 1...3 {
            clock.advance(by: 0.1)
            repository.refreshSpaces()
        }
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Mid-run partial observations below the floor must not prune")

        // Recovery: both displays enumerated → the label is preserved.
        bridge.managedSnapshotValue = .init(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201]]
        )
        clock.advance(by: 0.1)
        repository.refreshSpaces()
        XCTAssertEqual(repository.labels[201]?.name, "Work",
                       "Label must survive the recovery snapshot")
    }

    func testRefreshConvergesToStaleAfterConsecutiveAnomalyRefreshes() {
        let store = makeStore()
        try? store.save(PersistedSpaces(labels: [101: SpaceLabel(name: "Inbox")]))

        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: .init(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
        )
        let pair = SpaceStateManagerFactory.makePair(cgsBridge: bridge, store: store)
        XCTAssertEqual(pair.manager.spaces.map(\.id), [101, 102])

        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        for _ in 0..<(SpaceStateManager.maxConsecutiveAnomalyRetentions - 1) {
            pair.manager.refreshSpaces()
            XCTAssertEqual(pair.manager.spaces.map(\.id), [101, 102],
                           "Within the anomaly budget previous spaces are retained")
            XCTAssertFalse(pair.manager.isStaleSnapshot)
        }

        pair.manager.refreshSpaces()
        XCTAssertEqual(
            pair.manager.spaces,
            [],
            "Once the anomaly budget is exhausted the retained list is dropped and the state goes stale"
        )
        XCTAssertTrue(pair.manager.isStaleSnapshot)
        XCTAssertEqual(pair.queryService.name(for: 101), "Inbox", "Labels must survive the stale epoch")
        XCTAssertNil(pair.manager.labels[1], "Space 1 must not gain a label during a stale epoch")
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceStateManagerTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }

    private func makeSnapshot(ids: [Int], active: Int) -> CGSBridge.ManagedSnapshot {
        CGSBridge.ManagedSnapshot(
            spaces: ids.map { SpaceIdentity(id: $0, display: "display-a", kind: .desktop) },
            activeByDisplay: ["display-a": active],
            orderedIDsByDisplay: ["display-a": ids]
        )
    }
}
