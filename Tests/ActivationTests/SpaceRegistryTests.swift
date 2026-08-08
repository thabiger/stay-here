import XCTest
import Core
import TestHelpers

@MainActor
final class SpaceRegistryTests: XCTestCase {
    func testForwardsReadPropertiesToRepository() {
        let pair = SpaceStateManagerFactory.makePair(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: 101,
                managedSnapshotValue: CGSBridge.ManagedSnapshot(
                    spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                    activeByDisplay: ["display-a": 101],
                    orderedIDsByDisplay: ["display-a": [101]]
                )
            )
        )
        let registry: any SpaceRegistryProtocol = pair.queryService

        XCTAssertEqual(registry.activeSpaceID, pair.manager.activeSpaceID)
        XCTAssertEqual(registry.spaces.map(\.id), pair.manager.spaces.map(\.id))
        XCTAssertEqual(registry.labels, pair.manager.labels)
        XCTAssertEqual(registry.isStaleSnapshot, pair.manager.isStaleSnapshot)
        XCTAssertFalse(registry.isStaleSnapshot)
    }

    func testForwardsReadMethodsToRepository() {
        let pair = SpaceStateManagerFactory.makePair(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: 101,
                managedSnapshotValue: CGSBridge.ManagedSnapshot(
                    spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                    activeByDisplay: ["display-a": 101],
                    orderedIDsByDisplay: ["display-a": [101]]
                )
            )
        )
        let registry: any SpaceRegistryProtocol = pair.queryService

        // Verify initial state is readable through the query service
        let initialName = registry.name(for: 101)
        XCTAssertEqual(registry.orderedSpaceIDs(), [101])
        XCTAssertEqual(registry.activeNameSummary(), initialName)

        // Mutate state through the manager — rename space 101
        pair.manager.rename(spaceID: 101, name: "My Custom Space")

        // Query service must see the updated name (proves read/write split works
        // because both manager and queryService share the same underlying stateStore)
        XCTAssertEqual(registry.name(for: 101), "My Custom Space")
        XCTAssertNotEqual(registry.name(for: 101), initialName)

        // displayName should also reflect the change
        XCTAssertEqual(registry.displayName(for: 101), "My Custom Space")

        // activeNameSummary must update to reflect the renamed space
        XCTAssertEqual(registry.activeNameSummary(), "My Custom Space")

        // namespaceLabel and orderedSpaceIDs remain stable (rename does not affect ordering)
        let label = registry.namespaceLabel(for: 101)
        XCTAssertFalse(label.isEmpty)
        XCTAssertEqual(registry.orderedSpaceIDs(), [101])
    }
}
