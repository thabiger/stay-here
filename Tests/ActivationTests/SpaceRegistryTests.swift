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

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceRegistryTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
