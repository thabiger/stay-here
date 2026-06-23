import XCTest
import Core

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

        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())

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

        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let refreshSpaces = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())
        let switchSpace = SwitchSpaceUseCase(
            cgsBridge: bridge,
            repository: repository,
            refreshUseCase: refreshSpaces,
            logger: NoOpLogger()
        )
        let result = await switchSpace.execute(102)

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
        XCTAssertEqual(repository.activeSpaceID, 102)
    }

    func testRenamePersistsAcrossRepositoryInstances() {
        let store = makeStore()
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )

        let writer = SpaceStateManager(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            logger: NoOpLogger()
        )
        writer.rename(spaceID: 101, name: "Inbox")
        writer.persistNow()

        let reader = SpaceStateManager(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            logger: NoOpLogger()
        )

        XCTAssertEqual(reader.name(for: 101), "Inbox")
    }

    func testMoveDisplayOrderPersistsAcrossRepositoryInstances() {
        let store = makeStore()
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
            ],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101, 102, 103]]
        )

        let writer = SpaceStateManager(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            logger: NoOpLogger()
        )
        writer.moveDisplayOrder(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        writer.persistNow()

        let reader = SpaceStateManager(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            logger: NoOpLogger()
        )

        XCTAssertTrue(reader.usesCustomDisplayOrder)
        XCTAssertEqual(reader.orderedSpaceIDs(), [103, 101, 102])
    }

    func testInitDoesNotDropPersistedLabelsWhenSnapshotIsTransientlyEmpty() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")],
                displayOrder: [101],
                usesCustomDisplayOrder: false
            )
        )

        let repository = SpaceStateManager(
            store: store,
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: nil,
                managedSnapshotValue: .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
            ),
            logger: NoOpLogger()
        )

        XCTAssertEqual(repository.name(for: 101), "Inbox")
        XCTAssertNil(repository.labels[1], "Fallback space state must not be persisted as a real label")

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
                labels: [101: SpaceLabel(name: "Inbox")],
                displayOrder: [101],
                usesCustomDisplayOrder: false
            )
        )

        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())

        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )
        repository.refreshSpaces()

        XCTAssertEqual(repository.name(for: 101), "Inbox")
        XCTAssertEqual(repository.spaces.map(\.id), [101])
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceStateManagerTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
