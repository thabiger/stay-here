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
        name: String
    ) -> [Int: SpaceLabel] {
        labelStore.rename(spaceID: spaceID, name: name)
        persistNow()
        return labelStore.persistenceSnapshot()
    }

    public func persistNow() {
        labelStore.persistNow()
    }

    @discardableResult
    public func observe(
        spaces: [SpaceIdentity],
        observedDisplays: Set<String>
    ) -> [Int: SpaceLabel] {
        labelStore.observe(spaces: spaces, observedDisplays: observedDisplays)
        return labelStore.persistenceSnapshot()
    }

    // MARK: Snapshot

    public func persistenceSnapshot() -> [Int: SpaceLabel] {
        labelStore.persistenceSnapshot()
    }
}
