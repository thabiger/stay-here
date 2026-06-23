import XCTest
import Core

@MainActor
final class RefreshSpacesUseCaseTests: XCTestCase {
    func testExecuteAppliesSnapshotImmediately() {
        let repository = SpaceStateManager(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: 201,
                managedSnapshotValue: CGSBridge.ManagedSnapshot(
                    spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
                    activeByDisplay: ["display-b": 201],
                    orderedIDsByDisplay: ["display-b": [201]]
                )
            ),
            logger: NoOpLogger()
        )
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.execute()

        XCTAssertEqual(repository.activeSpaceID, 201)
        XCTAssertEqual(repository.spaces.map(\.id), [201])
    }

    func testExecuteAsyncAppliesSnapshot() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
                activeByDisplay: ["display-b": 201],
                orderedIDsByDisplay: ["display-b": [201]]
            )
        )
        let repository = SpaceStateManager(cgsBridge: bridge, logger: NoOpLogger())
        let useCase = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())

        useCase.executeAsync()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(repository.activeSpaceID, 201)
    }

    func testExecuteSoonRetriesUntilActiveSpaceChanges() async {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let repository = SpaceStateManager(cgsBridge: bridge, logger: NoOpLogger())
        let useCase = RefreshSpacesUseCase(
            repository: repository,
            refreshRetryLimit: 3,
            logger: NoOpLogger()
        )

        useCase.executeSoon()
        XCTAssertEqual(repository.activeSpaceID, 101)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(repository.activeSpaceID, 101)

        bridge.activeSpaceIDValue = 102
        bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 102],
            orderedIDsByDisplay: ["display-a": [102]]
        )

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(repository.activeSpaceID, 102)
    }
}
