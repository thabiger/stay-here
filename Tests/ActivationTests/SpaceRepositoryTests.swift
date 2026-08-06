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

        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
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

        let writer = SpaceStateManagerFactory.make(
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            store: store
        )
        writer.rename(spaceID: 101, name: "Inbox")
        writer.persistNow()

        let reader = SpaceStateManagerFactory.make(
            cgsBridge: MockCGSBridge(activeSpaceIDValue: 101, managedSnapshotValue: snapshot),
            store: store
        )

        XCTAssertEqual(reader.name(for: 101), "Inbox")
    }

    func testInitDoesNotDropPersistedLabelsWhenSnapshotIsTransientlyEmpty() {
        let store = makeStore()
        try? store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let repository = SpaceStateManagerFactory.make(
            cgsBridge: MockCGSBridge(
                activeSpaceIDValue: nil,
                managedSnapshotValue: .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
            ),
            store: store
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
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)

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
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102])

        // Phase 2: transient bad state — spaces only on display-b, focus on display-a → discovered empty.
        bridge.activeSpaceIDValue = 101
        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        repository.refreshSpaces()

        XCTAssertEqual(repository.spaces.map(\.id), [101, 102],
                       "Previous spaces must be retained, not replaced by the fallback/empty list")
        XCTAssertEqual(repository.name(for: 101), "Inbox")
        XCTAssertNil(repository.labels[1], "Synthetic fallback must never be persisted as a label")
        XCTAssertNil(repository.labels[201])

        repository.persistNow()   // flush any pending debounced write before reload
        let reloaded = store.load()
        XCTAssertEqual(reloaded.labels[101]?.name, "Inbox")
        XCTAssertNil(reloaded.labels[1])
        XCTAssertNil(reloaded.labels[201])
    }

    func testRefreshConvergesToFallbackAfterConsecutiveAnomalyRefreshes() {
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
        let repository = SpaceStateManagerFactory.make(cgsBridge: bridge, store: store)
        XCTAssertEqual(repository.spaces.map(\.id), [101, 102])

        bridge.managedSnapshotValue = .init(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        for _ in 0..<(SpaceStateManager.maxConsecutiveAnomalyRetentions - 1) {
            repository.refreshSpaces()
            XCTAssertEqual(repository.spaces.map(\.id), [101, 102],
                           "Within the anomaly budget previous spaces are retained")
        }

        repository.refreshSpaces()
        XCTAssertEqual(
            repository.spaces,
            [SpaceIdentity(id: 1, display: SpaceOrderingService.fallbackDisplay)],
            "Once the anomaly budget is exhausted the retained list is dropped and the fallback appears"
        )
        XCTAssertEqual(repository.name(for: 101), "Inbox", "Labels must survive the convergence fallback")
        XCTAssertNil(repository.labels[1], "Synthetic fallback must never be persisted as a label")
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceStateManagerTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
