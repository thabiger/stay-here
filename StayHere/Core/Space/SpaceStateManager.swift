import Foundation
import Combine

public final class SpaceStateManager: ObservableObject {
    public var spaces: [SpaceIdentity] { stateStore.spaces }
    public var activeSpaceID: Int? { stateStore.activeSpaceID }
    public var labels: [Int: SpaceLabel] { stateStore.labels }
    public var displayOrder: [Int] { stateStore.displayOrder }
    public var usesCustomDisplayOrder: Bool { stateStore.usesCustomDisplayOrder }
    public var desktopNumberBySpaceID: [Int: Int] { stateStore.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { stateStore.nativeOrderByDisplay }

    let cgsBridge: any CGSBridgeProtocol
    let stateStore: SpaceStateStore
    private let labelStore: SpaceLabelStore
    private let orderingService: SpaceOrderingService
    private let logger: any Logging
    private var stateStoreObserver: AnyCancellable?

    public init(
        store: SpaceStore = SpaceStore(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        labelStore: SpaceLabelStore? = nil,
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.logger = logger
        self.labelStore = labelStore ?? SpaceLabelStore(store: store, logger: logger)
        self.stateStore = SpaceStateStore()
        self.orderingService = SpaceOrderingService()
        self.stateStoreObserver = nil
        bindStateStore()
        syncPersistenceState()
        refreshSpaces()
    }

    public func applyManagedSnapshot(_ snapshot: CGSBridge.ManagedSnapshot) {
        apply(snapshot: snapshot)
    }

    public func refreshSpaces() {
        apply(snapshot: cgsBridge.managedSnapshot())
    }

    public func name(for spaceID: Int) -> String {
        labels[spaceID]?.name ?? "Unnamed space"
    }

    public func displayName(for spaceID: Int) -> String {
        let customName = name(for: spaceID)
        if customName != "Unnamed space" {
            return customName
        }
        return space(for: spaceID)?.systemName ?? customName
    }

    public func namespaceLabel(for spaceID: Int) -> String {
        orderingService.namespaceLabel(
            for: spaceID,
            spaces: spaces,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
    }

    public func space(for spaceID: Int) -> SpaceIdentity? {
        spaces.first(where: { $0.id == spaceID })
    }

    public func isSwitchableSpace(_ spaceID: Int) -> Bool {
        guard let space = space(for: spaceID) else { return false }
        return space.kind == .desktop
    }

    public func rename(spaceID: Int, name: String) {
        labelStore.rename(spaceID: spaceID, name: name, orderedSpaceIDs: orderedSpaceIDs())
        syncPersistenceState()
        persistNow()
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int) {
        labelStore.moveDisplayOrder(
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            currentOrderedSpaceIDs: orderedSpaceIDs()
        )
        syncPersistenceState()
        persistNow()
    }

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

    public func snapshotJSON() -> String {
        let snap = SpaceStateSnapshot(
            timestampISO8601: ISO8601DateFormatter().string(from: Date()),
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            labels: labels,
            displayOrder: orderedSpaceIDs()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snap), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    public func activeNameSummary() -> String {
        activeSpaceID.map { displayName(for: $0) } ?? "Unnamed space"
    }

    public func activeName() -> String {
        activeNameSummary()
    }

    public func persistNow() {
        labelStore.persistNow(orderedSpaceIDs: orderedSpaceIDs())
    }

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        stateStore.currentSwitchSnapshot()
    }

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
        labelStore.reconcileLabels(for: spaces, orderedSpaceIDs: orderedSpaceIDs())
        syncPersistenceState()
    }

    func syncPersistenceState() {
        let snapshot = labelStore.persistenceSnapshot()
        stateStore.syncPersistenceState(
            labels: snapshot.labels,
            displayOrder: snapshot.displayOrder,
            usesCustomDisplayOrder: snapshot.usesCustomDisplayOrder
        )
    }
}
