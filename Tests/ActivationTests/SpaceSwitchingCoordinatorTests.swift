import XCTest
@testable import Core

final class SpaceSwitchingCoordinatorTests: XCTestCase {
    func testSwitchToSpaceDelegatesAndSchedulesRefresh() {
        let stateStore = SpaceStateStore()
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
        let ordering = SpaceOrderingService()
        Self.applySnapshot(bridge.managedSnapshotValue, bridge: bridge, ordering: ordering, stateStore: stateStore)

        var scheduledTasks: [DispatchWorkItem] = []
        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: {
                ordering.orderedSpaceIDs(
                    spaces: stateStore.spaces,
                    displayOrder: stateStore.displayOrder,
                    usesCustomDisplayOrder: stateStore.usesCustomDisplayOrder,
                    desktopNumberBySpaceID: stateStore.desktopNumberBySpaceID
                )
            },
            refreshNow: {
                Self.applySnapshot(bridge.managedSnapshot(), bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            applySnapshot: { snapshot in
                Self.applySnapshot(snapshot, bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            scheduleAfter: { _, task in
                scheduledTasks.append(task)
            },
            logger: NoOpLogger()
        )

        let result = coordinator.switchToSpace(102)

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
        XCTAssertEqual(stateStore.activeSpaceID, 102)
        XCTAssertEqual(scheduledTasks.count, 1)
    }

    func testSwitchToNextAndPreviousUseEffectiveOrder() {
        let stateStore = SpaceStateStore()
        stateStore.syncPersistenceState(
            labels: [:],
            displayOrder: [103, 101, 102],
            usesCustomDisplayOrder: true
        )
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102, 103]]
            )
        )
        var postedIndexes: [Int] = []
        bridge.switchByDesktopShortcutHandler = { index in
            postedIndexes.append(index)
            switch postedIndexes.count {
            case 1:
                bridge.activeSpaceIDValue = 102
                bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
                    spaces: bridge.managedSnapshotValue.spaces,
                    activeByDisplay: ["display-a": 102],
                    orderedIDsByDisplay: ["display-a": [101, 102, 103]]
                )
            default:
                bridge.activeSpaceIDValue = 103
                bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
                    spaces: bridge.managedSnapshotValue.spaces,
                    activeByDisplay: ["display-a": 103],
                    orderedIDsByDisplay: ["display-a": [101, 102, 103]]
                )
            }
            return true
        }
        let ordering = SpaceOrderingService()
        Self.applySnapshot(bridge.managedSnapshotValue, bridge: bridge, ordering: ordering, stateStore: stateStore)

        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: {
                ordering.orderedSpaceIDs(
                    spaces: stateStore.spaces,
                    displayOrder: stateStore.displayOrder,
                    usesCustomDisplayOrder: stateStore.usesCustomDisplayOrder,
                    desktopNumberBySpaceID: stateStore.desktopNumberBySpaceID
                )
            },
            refreshNow: {
                Self.applySnapshot(bridge.managedSnapshot(), bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            applySnapshot: { snapshot in
                Self.applySnapshot(snapshot, bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            scheduleAfter: { _, _ in },
            logger: NoOpLogger()
        )

        coordinator.switchToNextSpace()
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
            spaces: bridge.managedSnapshotValue.spaces,
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101, 102, 103]]
        )
        Self.applySnapshot(bridge.managedSnapshotValue, bridge: bridge, ordering: ordering, stateStore: stateStore)
        coordinator.switchToPreviousSpace()

        XCTAssertEqual(postedIndexes, [2, 3])
    }

    func testSwitchToNextSpaceSkipsEmptyOrderedList() {
        let stateStore = SpaceStateStore()
        let bridge = MockCGSBridge()
        var postedShortcut = false

        bridge.switchByDesktopShortcutHandler = { _ in
            postedShortcut = true
            return true
        }

        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: { [] },
            refreshNow: {},
            applySnapshot: { _ in },
            scheduleAfter: { _, _ in },
            logger: NoOpLogger()
        )

        coordinator.switchToNextSpace()

        XCTAssertFalse(postedShortcut)
    }

    func testUnmatchedSwitchSchedulesRetryRefresh() {
        let stateStore = SpaceStateStore()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            ),
            switchByDesktopShortcutHandler: { _ in true }
        )
        let ordering = SpaceOrderingService()
        Self.applySnapshot(bridge.managedSnapshotValue, bridge: bridge, ordering: ordering, stateStore: stateStore)

        var scheduledTasks: [DispatchWorkItem] = []
        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 1,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: {
                ordering.orderedSpaceIDs(
                    spaces: stateStore.spaces,
                    displayOrder: stateStore.displayOrder,
                    usesCustomDisplayOrder: stateStore.usesCustomDisplayOrder,
                    desktopNumberBySpaceID: stateStore.desktopNumberBySpaceID
                )
            },
            refreshNow: {
                Self.applySnapshot(bridge.managedSnapshot(), bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            applySnapshot: { snapshot in
                Self.applySnapshot(snapshot, bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            scheduleAfter: { _, task in
                scheduledTasks.append(task)
            },
            logger: NoOpLogger()
        )

        let result = coordinator.switchToSpace(102)

        XCTAssertEqual(result, .switchUnmatched(index: 2, expectedSpaceID: 102, actualSpaceID: 101))
        XCTAssertEqual(scheduledTasks.count, 1)
    }

    func testRefreshSpacesSoonStopsRetryingAfterActiveSpaceChanges() {
        let stateStore = SpaceStateStore()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let ordering = SpaceOrderingService()
        Self.applySnapshot(bridge.managedSnapshotValue, bridge: bridge, ordering: ordering, stateStore: stateStore)

        var scheduledTasks: [DispatchWorkItem] = []
        var refreshCount = 0
        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: { [101] },
            refreshNow: {
                refreshCount += 1
                Self.applySnapshot(bridge.managedSnapshot(), bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            applySnapshot: { snapshot in
                Self.applySnapshot(snapshot, bridge: bridge, ordering: ordering, stateStore: stateStore)
            },
            scheduleAfter: { _, task in
                scheduledTasks.append(task)
            },
            refreshRetryLimit: 3,
            logger: NoOpLogger()
        )

        coordinator.refreshSpacesSoon()
        bridge.activeSpaceIDValue = 102
        bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 102],
            orderedIDsByDisplay: ["display-a": [102]]
        )
        scheduledTasks.first?.perform()

        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(stateStore.activeSpaceID, 102)
        XCTAssertEqual(scheduledTasks.count, 1)
    }

    func testRefreshSpacesAsyncAppliesSnapshotOnMainThread() {
        let stateStore = SpaceStateStore()
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
                activeByDisplay: ["display-b": 201],
                orderedIDsByDisplay: ["display-b": [201]]
            )
        )
        let ordering = SpaceOrderingService()
        let appliedOnMainThread = expectation(description: "applied on main thread")

        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            stateStore: stateStore,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            orderedSpaceIDs: { [] },
            refreshNow: {},
            applySnapshot: { snapshot in
                XCTAssertTrue(Thread.isMainThread)
                Self.applySnapshot(snapshot, bridge: bridge, ordering: ordering, stateStore: stateStore)
                appliedOnMainThread.fulfill()
            },
            logger: NoOpLogger()
        )

        coordinator.refreshSpacesAsync()

        wait(for: [appliedOnMainThread], timeout: 1.0)
        XCTAssertEqual(stateStore.activeSpaceID, 201)
    }

    private static func applySnapshot(
        _ snapshot: CGSBridge.ManagedSnapshot,
        bridge: MockCGSBridge,
        ordering: SpaceOrderingService,
        stateStore: SpaceStateStore
    ) {
        stateStore.applyDerivedState(
            ordering.deriveState(
                snapshot: snapshot,
                globalActiveID: bridge.activeSpaceID(),
                previousActiveID: stateStore.activeSpaceID
            )
        )
    }
}
