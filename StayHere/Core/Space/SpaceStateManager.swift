import Foundation

@MainActor
public final class SpaceStateManager {
    public nonisolated static let maxConsecutiveAnomalyRetentions = 3

    public var spaces: [SpaceIdentity] { stateStore.spaces }
    public var activeSpaceID: Int? { stateStore.activeSpaceID }
    public var labels: [Int: SpaceLabel] { stateStore.labels }
    public var desktopNumberBySpaceID: [Int: Int] { stateStore.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { stateStore.nativeOrderByDisplay }
    public var isStaleSnapshot: Bool { stateStore.isStaleSnapshot }

    let cgsBridge: any CGSBridgeProtocol
    let stateStore: SpaceStateStore
    private let persistenceCoordinator: SpacePersistenceCoordinator
    private let orderingService: SpaceOrderingService
    private let logger: any Logging
    private var consecutiveAnomalyRetentions = 0

    public init(
        cgsBridge: any CGSBridgeProtocol,
        stateStore: SpaceStateStore,
        persistenceCoordinator: SpacePersistenceCoordinator,
        orderingService: SpaceOrderingService,
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.logger = logger
        self.stateStore = stateStore
        self.orderingService = orderingService
        self.persistenceCoordinator = persistenceCoordinator
        let initialPersistence = persistenceCoordinator.persistenceSnapshot()
        stateStore.syncPersistenceState(labels: initialPersistence)
        refreshSpaces()
    }

    // MARK: Snapshot Application

    public func applyManagedSnapshot(_ snapshot: CGSBridge.ManagedSnapshot) {
        apply(snapshot: snapshot)
    }

    public func refreshSpaces() {
        apply(snapshot: cgsBridge.managedSnapshot())
    }

    // MARK: Persistence Coordination

    public func rename(spaceID: Int, name: String) {
        let labels = persistenceCoordinator.rename(
            spaceID: spaceID,
            name: name
        )
        stateStore.syncPersistenceState(labels: labels)
    }

    public func persistNow() {
        persistenceCoordinator.persistNow()
    }

    // MARK: Private

    private func apply(snapshot: CGSBridge.ManagedSnapshot) {
        let derivedState = orderingService.deriveState(
            snapshot: snapshot,
            globalActiveID: cgsBridge.activeSpaceID(),
            previousActiveID: stateStore.activeSpaceID,
            previousSpaces: stateStore.spaces,
            previousNativeOrderByDisplay: stateStore.nativeOrderByDisplay,
            previousDesktopNumberBySpaceID: stateStore.desktopNumberBySpaceID,
            consecutiveAnomalyRetentions: consecutiveAnomalyRetentions,
            maxConsecutiveAnomalyRetentions: Self.maxConsecutiveAnomalyRetentions
        )
        stateStore.applyDerivedState(derivedState)
        if !snapshot.spaces.isEmpty,
           !derivedState.isStaleSnapshot,
           !derivedState.retainedPreviousSpaces {
            observePersistedSpaces(snapshot: snapshot)
        }
        consecutiveAnomalyRetentions = derivedState.retainedPreviousSpaces ? consecutiveAnomalyRetentions + 1 : 0
    }

    private func observePersistedSpaces(snapshot: CGSBridge.ManagedSnapshot) {
        let observedDisplays = Set(snapshot.spaces.map(\.display))
        let labels = persistenceCoordinator.observe(
            spaces: snapshot.spaces,
            observedDisplays: observedDisplays
        )
        stateStore.syncPersistenceState(labels: labels)
    }
}

extension SpaceStateManager: SpaceRenaming {}
extension SpaceStateManager: SpaceSnapshotRefreshable {}
