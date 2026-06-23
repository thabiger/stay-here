import Foundation

/// Owns the `SpaceLabelStore` and coordinates persistence operations
/// with `SpaceStateStore`, encapsulating the label-store → sync-persistence → persist-now
/// pattern that was duplicated across multiple methods in `SpaceStateManager`.
@MainActor
public final class SpacePersistenceCoordinator {
    let labelStore: SpaceLabelStore
    private let stateStore: SpaceStateStore

    public init(
        store: SpaceStore = SpaceStore(),
        stateStore: SpaceStateStore,
        labelStore: SpaceLabelStore? = nil,
        logger: any Logging
    ) {
        self.labelStore = labelStore ?? SpaceLabelStore(store: store, logger: logger)
        self.stateStore = stateStore
        syncPersistenceState()
    }

    // MARK: Public API

    public func rename(spaceID: Int, name: String, orderedSpaceIDs: [Int]) {
        labelStore.rename(spaceID: spaceID, name: name, orderedSpaceIDs: orderedSpaceIDs)
        syncPersistenceState()
        persistNow(orderedSpaceIDs: orderedSpaceIDs)
    }

    public func moveDisplayOrder(
        fromOffsets: IndexSet,
        toOffset: Int,
        currentOrderedSpaceIDs: [Int]
    ) {
        labelStore.moveDisplayOrder(
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            currentOrderedSpaceIDs: currentOrderedSpaceIDs
        )
        syncPersistenceState()
        persistNow(orderedSpaceIDs: currentOrderedSpaceIDs)
    }

    public func persistNow(orderedSpaceIDs: [Int]) {
        labelStore.persistNow(orderedSpaceIDs: orderedSpaceIDs)
    }

    public func reconcileLabels(
        for spaces: [SpaceIdentity],
        orderedSpaceIDs: [Int]
    ) {
        labelStore.reconcileLabels(for: spaces, orderedSpaceIDs: orderedSpaceIDs)
        syncPersistenceState()
    }

    // MARK: Internal

    /// Copies current labels/displayOrder from the label store into the state store
    /// so that the rest of the system sees a consistent view.
    func syncPersistenceState() {
        let snapshot = labelStore.persistenceSnapshot()
        stateStore.syncPersistenceState(
            labels: snapshot.labels,
            displayOrder: snapshot.displayOrder,
            usesCustomDisplayOrder: snapshot.usesCustomDisplayOrder
        )
    }
}
