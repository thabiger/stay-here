import XCTest
@testable import Core

final class SpaceSwitchingCoordinatorTests: XCTestCase {
    func testSwitchToSpaceDelegatesAndSchedulesRefresh() {
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

        let (repository, coordinator) = makeFixtures(bridge: bridge)

        let result = coordinator.switchToSpace(102)

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
        XCTAssertEqual(repository.activeSpaceID, 102)
    }

    func testSwitchToNextAndPreviousUseEffectiveOrder() {
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

        let (repository, coordinator) = makeFixtures(bridge: bridge)
        repository.stateStore.syncPersistenceState(
            labels: [:],
            displayOrder: [103, 101, 102],
            usesCustomDisplayOrder: true
        )
        repository.refreshSpaces()

        coordinator.switchToNextSpace()
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
            spaces: bridge.managedSnapshotValue.spaces,
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101, 102, 103]]
        )
        repository.refreshSpaces()
        coordinator.switchToPreviousSpace()

        XCTAssertEqual(postedIndexes, [2, 3])
    }

    func testSwitchToNextSpaceSkipsEmptyOrderedList() {
        let bridge = MockCGSBridge()
        var postedShortcut = false

        bridge.switchByDesktopShortcutHandler = { _ in
            postedShortcut = true
            return true
        }

        let (_, coordinator) = makeFixtures(bridge: bridge)

        coordinator.switchToNextSpace()

        XCTAssertFalse(postedShortcut)
    }

    func testUnmatchedSwitchSchedulesRetryRefresh() {
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

        var scheduledSoon = false
        let (_, coordinator) = makeFixtures(
            bridge: bridge,
            switcherService: SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 1,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            scheduleRefreshSoon: {
                scheduledSoon = true
            }
        )

        let result = coordinator.switchToSpace(102)

        XCTAssertEqual(result, .switchUnmatched(index: 2, expectedSpaceID: 102, actualSpaceID: 101))
        XCTAssertTrue(scheduledSoon)
    }

    private func makeFixtures(
        bridge: MockCGSBridge,
        switcherService: SpaceSwitcherService? = nil,
        scheduleRefreshSoon: @escaping () -> Void = {}
    ) -> (SpaceRepository, SpaceSwitchingCoordinator) {
        let repository = SpaceRepository(cgsBridge: bridge, logger: NoOpLogger())
        let coordinator = SpaceSwitchingCoordinator(
            cgsBridge: bridge,
            repository: repository,
            switcherService: switcherService ?? SpaceSwitcherService(
                cgsBridge: bridge,
                refreshRetryLimit: 0,
                waitForRefresh: { _ in },
                logger: NoOpLogger()
            ),
            refreshSpaces: { repository.applyManagedSnapshot(bridge.managedSnapshot()) },
            scheduleRefreshSoon: scheduleRefreshSoon,
            logger: NoOpLogger()
        )
        return (repository, coordinator)
    }
}
