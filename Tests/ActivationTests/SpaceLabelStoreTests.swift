import XCTest
import Core

final class SpaceLabelStoreTests: XCTestCase {
    func testLoadsPersistedStateFromStore() throws {
        let store = makeStore()
        try store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")],
                displayOrder: [101, 102],
                usesCustomDisplayOrder: true
            )
        )

        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        XCTAssertEqual(labelStore.labels[101]?.name, "Inbox")
        XCTAssertEqual(labelStore.displayOrder, [101, 102])
        XCTAssertTrue(labelStore.usesCustomDisplayOrder)
    }

    func testReconcileAddsMissingLabelsAndRemovesUnknownSpaces() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.rename(spaceID: 999, name: "Old", orderedSpaceIDs: [999])
        labelStore.persistNow(orderedSpaceIDs: [999])

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.reconcileLabels(
            for: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
            ],
            orderedSpaceIDs: [101, 102]
        )

        XCTAssertEqual(reloaded.labels[101]?.name, "Unnamed space")
        XCTAssertEqual(reloaded.labels[102]?.name, "Unnamed space")
        XCTAssertNil(reloaded.labels[999])
    }

    func testMoveDisplayOrderPersistsCustomOrdering() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.moveDisplayOrder(
            fromOffsets: IndexSet(integer: 2),
            toOffset: 0,
            currentOrderedSpaceIDs: [101, 102, 103]
        )
        labelStore.persistNow(orderedSpaceIDs: labelStore.displayOrder)

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())

        XCTAssertTrue(reloaded.usesCustomDisplayOrder)
        XCTAssertEqual(reloaded.displayOrder, [103, 101, 102])
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLabelStoreTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
