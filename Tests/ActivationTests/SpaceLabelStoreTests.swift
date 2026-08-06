import XCTest
@testable import Core

@MainActor
final class SpaceLabelStoreTests: XCTestCase {
    func testLoadsPersistedStateFromStore() throws {
        let store = makeStore()
        try store.save(
            PersistedSpaces(
                labels: [101: SpaceLabel(name: "Inbox")]
            )
        )

        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        XCTAssertEqual(labelStore.labels[101]?.name, "Inbox")
    }

    func testReconcileAddsMissingLabelsAndRemovesUnknownSpaces() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())

        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.reconcileLabels(
            for: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
            ]
        )

        XCTAssertEqual(reloaded.labels[101]?.name, "Unnamed space")
        XCTAssertEqual(reloaded.labels[102]?.name, "Unnamed space")
        XCTAssertNil(reloaded.labels[999])
    }

    func testReconcileDoesNotDeleteLabelsForEmptyOrSyntheticFallbackInput() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())
        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.reconcileLabels(for: [])
        XCTAssertEqual(reloaded.labels[999]?.name, "Old", "Empty input must not delete labels")

        reloaded.reconcileLabels(for: [SpaceIdentity(id: 1, display: SpaceOrderingService.fallbackDisplay)])
        XCTAssertEqual(reloaded.labels[999]?.name, "Old", "Synthetic fallback input must not delete labels")
        XCTAssertNil(reloaded.labels[1])
    }

    func testReconcileBlocksMixedListContainingSyntheticFallback() {
        let store = makeStore()
        let labelStore = SpaceLabelStore(store: store, logger: NoOpLogger())
        labelStore.rename(spaceID: 999, name: "Old")
        labelStore.persistNow()

        let reloaded = SpaceLabelStore(store: store, logger: NoOpLogger())
        reloaded.reconcileLabels(
            for: [
                SpaceIdentity(id: 1, display: SpaceOrderingService.fallbackDisplay),
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop)
            ]
        )
        XCTAssertEqual(reloaded.labels[999]?.name, "Old", "Any synthetic fallback in the input must block reconcile")
        XCTAssertNil(reloaded.labels[101], "Reconcile must not run when a synthetic fallback is present")
    }

    private func makeStore() -> SpaceStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLabelStoreTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        return SpaceStore(fileURL: fileURL)
    }
}
