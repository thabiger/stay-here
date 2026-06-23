import XCTest
import Core

@MainActor
final class SpaceRegistryTests: XCTestCase {
    func testForwardsReadPropertiesToRepository() {
        let repository = SpaceStateManager(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: 101,
                managedSnapshotValue: CGSBridge.ManagedSnapshot(
                    spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                    activeByDisplay: ["display-a": 101],
                    orderedIDsByDisplay: ["display-a": [101]]
                )
            ),
            logger: NoOpLogger()
        )
        let registry: any SpaceRegistryProtocol = repository

        XCTAssertEqual(registry.activeSpaceID, repository.activeSpaceID)
        XCTAssertEqual(registry.spaces.map(\.id), repository.spaces.map(\.id))
        XCTAssertEqual(registry.labels, repository.labels)
        XCTAssertEqual(registry.displayOrder, repository.displayOrder)
    }

    func testForwardsReadMethodsToRepository() {
        let repository = SpaceStateManager(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: 101,
                managedSnapshotValue: CGSBridge.ManagedSnapshot(
                    spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                    activeByDisplay: ["display-a": 101],
                    orderedIDsByDisplay: ["display-a": [101]]
                )
            ),
            logger: NoOpLogger()
        )
        let registry: any SpaceRegistryProtocol = repository

        XCTAssertEqual(registry.name(for: 101), repository.name(for: 101))
        XCTAssertEqual(registry.displayName(for: 101), repository.displayName(for: 101))
        XCTAssertEqual(registry.namespaceLabel(for: 101), repository.namespaceLabel(for: 101))
        XCTAssertEqual(registry.orderedSpaceIDs(), repository.orderedSpaceIDs())
        XCTAssertEqual(registry.activeNameSummary(), repository.activeNameSummary())
    }
}
