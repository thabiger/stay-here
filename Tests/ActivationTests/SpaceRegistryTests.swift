import XCTest
import Core

final class SpaceRegistryTests: XCTestCase {
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

        let registry = SpaceRegistry(store: store, cgsBridge: bridge)

        XCTAssertEqual(registry.activeSpaceID, 201)
        XCTAssertEqual(registry.spaces.map(\.id), [201, 202])
        XCTAssertEqual(registry.desktopNumberBySpaceID[101], 1)
        XCTAssertEqual(registry.desktopNumberBySpaceID[102], 2)
        XCTAssertEqual(registry.desktopNumberBySpaceID[201], 1)
    }

    func testSwitchToSpaceUsesInjectedBridgeShortcutPosting() {
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

        let registry = SpaceRegistry(store: store, cgsBridge: bridge)
        let result = registry.switchToSpace(102)

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
        XCTAssertEqual(registry.activeSpaceID, 102)
    }

    func testRenamePersistsAcrossRegistryInstances() {
        let store = makeStore()
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )

        let writer = SpaceRegistry(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot)
        )
        writer.rename(spaceID: 101, name: "Inbox")
        writer.persistNow()

        let reader = SpaceRegistry(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot)
        )

        XCTAssertEqual(reader.name(for: 101), "Inbox")
    }

    func testMoveDisplayOrderPersistsAcrossRegistryInstances() {
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

        let writer = SpaceRegistry(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot)
        )
        writer.moveDisplayOrder(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        writer.persistNow()

        let reader = SpaceRegistry(
            store: store,
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot)
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

        let registry = SpaceRegistry(
            store: store,
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: nil,
                managedSnapshotValue: .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
            )
        )

        XCTAssertEqual(registry.name(for: 101), "Inbox")
        XCTAssertNil(registry.labels[1], "Fallback space state must not be persisted as a real label")

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

        let registry = SpaceRegistry(store: store, cgsBridge: bridge)

        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 101, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 101],
            orderedIDsByDisplay: ["display-a": [101]]
        )
        registry.refreshSpaces()

        XCTAssertEqual(registry.name(for: 101), "Inbox")
        XCTAssertEqual(registry.spaces.map(\.id), [101])
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceRegistryTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
