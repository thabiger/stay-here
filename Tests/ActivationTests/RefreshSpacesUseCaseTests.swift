import XCTest
import Core

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

    func testExecuteAsyncAppliesSnapshot() {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 201,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
                activeByDisplay: ["display-b": 201],
                orderedIDsByDisplay: ["display-b": [201]]
            )
        )
        let repository = SpaceStateManager(cgsBridge: bridge, logger: NoOpLogger())
        let applied = expectation(description: "applied")
        let useCase = RefreshSpacesUseCase(
            repository: repository,
            mainExecutor: { task in
                DispatchQueue.main.async {
                    task.perform()
                    applied.fulfill()
                }
            },
            logger: NoOpLogger()
        )

        useCase.executeAsync()

        wait(for: [applied], timeout: 1.0)
        XCTAssertEqual(repository.activeSpaceID, 201)
    }

    func testExecuteSoonRetriesUntilActiveSpaceChanges() {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101]]
            )
        )
        let repository = SpaceStateManager(cgsBridge: bridge, logger: NoOpLogger())

        var scheduledTasks: [DispatchWorkItem] = []
        let useCase = RefreshSpacesUseCase(
            repository: repository,
            mainExecutor: { $0.perform() },
            scheduleAfter: { _, task in
                scheduledTasks.append(task)
            },
            refreshRetryLimit: 3,
            logger: NoOpLogger()
        )

        useCase.executeSoon()
        XCTAssertEqual(repository.activeSpaceID, 101)
        XCTAssertEqual(scheduledTasks.count, 1)

        scheduledTasks.first?.perform()
        XCTAssertEqual(repository.activeSpaceID, 101)
        XCTAssertEqual(scheduledTasks.count, 2)

        bridge.activeSpaceIDValue = 102
        bridge.managedSnapshotValue = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 102, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 102],
            orderedIDsByDisplay: ["display-a": [102]]
        )
        scheduledTasks[1].perform()
        XCTAssertEqual(repository.activeSpaceID, 102)
        XCTAssertEqual(scheduledTasks.count, 2)
    }
}
