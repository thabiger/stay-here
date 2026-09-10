import Foundation
import Combine

@MainActor
public final class SpaceQueryService {
    public let objectWillChange = ObservableObjectPublisher()

    public var spaces: [SpaceIdentity] { stateStore.spaces }
    public var activeSpaceID: Int? { stateStore.activeSpaceID }
    public var labels: [Int: SpaceLabel] { stateStore.labels }
    public var desktopNumberBySpaceID: [Int: Int] { stateStore.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { stateStore.nativeOrderByDisplay }
    public var isStaleSnapshot: Bool { stateStore.isStaleSnapshot }

    private let stateStore: SpaceStateStore
    private let orderingService: SpaceOrderingService
    private let nameProvider: SpaceDisplayNameProvider
    private let snapshotBuilder: SpaceSnapshotBuilder
    private var stateStoreObserver: AnyCancellable?

    /// Cached sorted space IDs — invalidated on every state change so the sort
    /// runs at most once per update rather than on every caller invocation.
    private var cachedOrderedSpaceIDs: [Int]?
    private var cachedSwitchableOrderedSpaceIDs: [Int]?

    public init(
        stateStore: SpaceStateStore,
        orderingService: SpaceOrderingService = SpaceOrderingService(),
        nameProvider: SpaceDisplayNameProvider = SpaceDisplayNameProvider(),
        snapshotBuilder: SpaceSnapshotBuilder = SpaceSnapshotBuilder()
    ) {
        self.stateStore = stateStore
        self.orderingService = orderingService
        self.nameProvider = nameProvider
        self.snapshotBuilder = snapshotBuilder
        self.stateStoreObserver = stateStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.invalidateOrderingCache()
        }
    }

    private func invalidateOrderingCache() {
        cachedOrderedSpaceIDs = nil
        cachedSwitchableOrderedSpaceIDs = nil
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

    // MARK: Space Ordering

    public func orderedSpaceIDs() -> [Int] {
        if let cached = cachedOrderedSpaceIDs { return cached }
        let result = orderingService.orderedSpaceIDs(
            spaces: spaces,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
        cachedOrderedSpaceIDs = result
        return result
    }

    public func switchableOrderedSpaceIDs() -> [Int] {
        if let cached = cachedSwitchableOrderedSpaceIDs { return cached }
        let result = orderingService.switchableOrderedSpaceIDs(
            spaces: spaces,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
        cachedSwitchableOrderedSpaceIDs = result
        return result
    }

    // MARK: JSON Snapshot

    public func snapshotJSON() -> String {
        snapshotBuilder.json(
            spaces: stateStore.spaces,
            labels: stateStore.labels,
            activeSpaceID: stateStore.activeSpaceID
        )
    }

    // MARK: Snapshot (for switching)

    public func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        stateStore.currentSwitchSnapshot()
    }
}

extension SpaceQueryService: SpaceRegistryProtocol {}
extension SpaceQueryService: SpaceSnapshotBuilding {}
extension SpaceQueryService: SpaceSwitchSnapshotProviding {}
