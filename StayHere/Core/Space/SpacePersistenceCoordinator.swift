import Foundation

/// Owns the `SpaceLabelStore` and coordinates persistence operations,
/// encapsulating the label-store → persist-now pattern.
@MainActor
public final class SpacePersistenceCoordinator {
    let labelStore: SpaceLabelStore

    public init(
        store: SpaceStore = SpaceStore(),
        labelStore: SpaceLabelStore? = nil,
        logger: any Logging
    ) {
        self.labelStore = labelStore ?? SpaceLabelStore(store: store, logger: logger)
    }

    // MARK: Public API

    @discardableResult
    public func rename(
        spaceID: Int,
        name: String,
        orderedSpaceIDs: [Int]
    ) -> (labels: [Int: SpaceLabel], displayOrder: [Int], usesCustomDisplayOrder: Bool) {
        labelStore.rename(spaceID: spaceID, name: name, orderedSpaceIDs: orderedSpaceIDs)
        persistNow(orderedSpaceIDs: orderedSpaceIDs)
        return labelStore.persistenceSnapshot()
    }

    @discardableResult
    public func moveDisplayOrder(
        fromOffsets: IndexSet,
        toOffset: Int,
        currentOrderedSpaceIDs: [Int]
    ) -> (labels: [Int: SpaceLabel], displayOrder: [Int], usesCustomDisplayOrder: Bool) {
        labelStore.moveDisplayOrder(
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            currentOrderedSpaceIDs: currentOrderedSpaceIDs
        )
        persistNow(orderedSpaceIDs: currentOrderedSpaceIDs)
        return labelStore.persistenceSnapshot()
    }

    public func persistNow(orderedSpaceIDs: [Int]) {
        labelStore.persistNow(orderedSpaceIDs: orderedSpaceIDs)
    }

    @discardableResult
    public func reconcileLabels(
        for spaces: [SpaceIdentity],
        orderedSpaceIDs: [Int]
    ) -> (labels: [Int: SpaceLabel], displayOrder: [Int], usesCustomDisplayOrder: Bool) {
        labelStore.reconcileLabels(for: spaces, orderedSpaceIDs: orderedSpaceIDs)
        return labelStore.persistenceSnapshot()
    }

    // MARK: Snapshot

    public func persistenceSnapshot() -> (
        labels: [Int: SpaceLabel],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool
    ) {
        labelStore.persistenceSnapshot()
    }
}
