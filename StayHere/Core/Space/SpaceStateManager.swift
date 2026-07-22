import Foundation
import Combine

@MainActor
public final class SpaceStateManager {
    public let objectWillChange = ObservableObjectPublisher()
    public var spaces: [SpaceIdentity] { stateStore.spaces }
    public var activeSpaceID: Int? { stateStore.activeSpaceID }
    public var labels: [Int: SpaceLabel] { stateStore.labels }
    public var displayOrder: [Int] { stateStore.displayOrder }
    public var usesCustomDisplayOrder: Bool { stateStore.usesCustomDisplayOrder }
    public var desktopNumberBySpaceID: [Int: Int] { stateStore.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { stateStore.nativeOrderByDisplay }

    let cgsBridge: any CGSBridgeProtocol
    let stateStore: SpaceStateStore
    private let persistenceCoordinator: SpacePersistenceCoordinator
    private let orderingService: SpaceOrderingService
    private let nameProvider: SpaceDisplayNameProvider
    private let snapshotBuilder: SpaceSnapshotBuilder
    private let logger: any Logging
    private var stateStoreObserver: AnyCancellable?

    public init(
        cgsBridge: any CGSBridgeProtocol,
        stateStore: SpaceStateStore,
        persistenceCoordinator: SpacePersistenceCoordinator,
        orderingService: SpaceOrderingService,
        nameProvider: SpaceDisplayNameProvider,
        snapshotBuilder: SpaceSnapshotBuilder,
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.logger = logger
        self.stateStore = stateStore
        self.orderingService = orderingService
        self.nameProvider = nameProvider
        self.snapshotBuilder = snapshotBuilder
        self.persistenceCoordinator = persistenceCoordinator
        self.stateStoreObserver = nil
        bindStateStore()
        // Load persisted labels/displayOrder into stateStore before first snapshot
        let initialPersistence = persistenceCoordinator.persistenceSnapshot()
        stateStore.syncPersistenceState(
            labels: initialPersistence.labels,
            displayOrder: initialPersistence.displayOrder,
            usesCustomDisplayOrder: initialPersistence.usesCustomDisplayOrder
        )
        refreshSpaces()
    }

    // MARK: Snapshot Application

    public func applyManagedSnapshot(_ snapshot: CGSBridge.ManagedSnapshot) {
        apply(snapshot: snapshot)
    }

    public func refreshSpaces() {
        apply(snapshot: cgsBridge.managedSnapshot())
    }

    // MARK: Name Formatting

    public func name(for spaceID: Int) -> String {
        nameProvider.name(for: spaceID, labels: stateStore.labels)
    }

    public func displayName(for spaceID: Int) -> String {
        nameProvider.displayName(for: spaceID, labels: stateStore.labels, spaces: stateStore.spaces)
    }

    public func activeNameSummary() -> String {
        nameProvider.activeNameSummary(
            activeSpaceID: stateStore.activeSpaceID,
            labels: stateStore.labels,
            spaces: stateStore.spaces
        )
    }

    public func activeName() -> String {
        nameProvider.activeName(
            activeSpaceID: stateStore.activeSpaceID,
            labels: stateStore.labels,
            spaces: stateStore.spaces
        )
    }

    // MARK: Namespace Label

    public func namespaceLabel(for spaceID: Int) -> String {
        orderingService.namespaceLabel(
            for: spaceID,
            spaces: spaces,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
    }

    // MARK: Space Lookup & Queries

    public func space(for spaceID: Int) -> SpaceIdentity? {
        spaces.first(where: { $0.id == spaceID })
    }

    public func isSwitchableSpace(_ spaceID: Int) -> Bool {
        guard let space = space(for: spaceID) else { return false }
        return space.kind == .desktop
    }

    // MARK: Persistence Coordination

    public func rename(spaceID: Int, name: String) {
        let snapshot = persistenceCoordinator.rename(
            spaceID: spaceID,
            name: name,
            orderedSpaceIDs: orderedSpaceIDs()
        )
        stateStore.syncPersistenceState(
            labels: snapshot.labels,
            displayOrder: snapshot.displayOrder,
            usesCustomDisplayOrder: snapshot.usesCustomDisplayOrder
        )
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int) {
        let snapshot = persistenceCoordinator.moveDisplayOrder(
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            currentOrderedSpaceIDs: orderedSpaceIDs()
        )
        stateStore.syncPersistenceState(
            labels: snapshot.labels,
            displayOrder: snapshot.displayOrder,
            usesCustomDisplayOrder: snapshot.usesCustomDisplayOrder
        )
    }

    public func persistNow() {
        persistenceCoordinator.persistNow(orderedSpaceIDs: orderedSpaceIDs())
    }

    // MARK: Space Ordering

    public func orderedSpaceIDs() -> [Int] {
        orderingService.orderedSpaceIDs(
            spaces: spaces,
            displayOrder: displayOrder,
            usesCustomDisplayOrder: usesCustomDisplayOrder,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
    }

    public func switchableOrderedSpaceIDs() -> [Int] {
        orderingService.switchableOrderedSpaceIDs(
            spaces: spaces,
            displayOrder: displayOrder,
            usesCustomDisplayOrder: usesCustomDisplayOrder,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
    }

    // MARK: JSON Snapshot

    public func snapshotJSON() -> String {
        snapshotBuilder.json(
            spaces: stateStore.spaces,
            labels: stateStore.labels,
            activeSpaceID: stateStore.activeSpaceID,
            displayOrder: orderedSpaceIDs()
        )
    }

    // MARK: Snapshot (for switching)

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        stateStore.currentSwitchSnapshot()
    }

    // MARK: Private

    private func bindStateStore() {
        stateStoreObserver = stateStore.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func apply(snapshot: CGSBridge.ManagedSnapshot) {
        let derivedState = orderingService.deriveState(
            snapshot: snapshot,
            globalActiveID: cgsBridge.activeSpaceID(),
            previousActiveID: stateStore.activeSpaceID
        )
        let spacesChanged = derivedState.spaces != stateStore.spaces
        stateStore.applyDerivedState(derivedState)
        if spacesChanged, snapshot.spaces.isEmpty == false {
            reconcilePersistedSpaces()
        }
    }

    private func reconcilePersistedSpaces() {
        let snapshot = persistenceCoordinator.reconcileLabels(
            for: stateStore.spaces,
            orderedSpaceIDs: orderedSpaceIDs()
        )
        stateStore.syncPersistenceState(
            labels: snapshot.labels,
            displayOrder: snapshot.displayOrder,
            usesCustomDisplayOrder: snapshot.usesCustomDisplayOrder
        )
    }
}

extension SpaceStateManager: SpaceRegistryProtocol {}
extension SpaceStateManager: SpaceRenaming {}
extension SpaceStateManager: SpaceReordering {}
extension SpaceStateManager: SpaceSnapshotBuilding {}
extension SpaceStateManager: SpaceSnapshotRefreshable {}
extension SpaceStateManager: SpaceSwitchSnapshotProviding {}
