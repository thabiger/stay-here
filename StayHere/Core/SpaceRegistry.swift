import Foundation
import Combine
import AppKit

public final class SpaceRegistry: ObservableObject {
    public enum SwitchResult: Equatable {
        case switched
        case alreadyActive
        case unknownSpace
        case unsupportedSpaceKind
        case unsupportedDesktop(index: Int)
        case eventPostFailed(index: Int)
        case switchUnmatched(index: Int, expectedSpaceID: Int, actualSpaceID: Int?)
    }

    public let objectWillChange = ObservableObjectPublisher()

    public var spaces: [SpaceIdentity] { stateStore.spaces }
    public var activeSpaceID: Int? { stateStore.activeSpaceID }
    public var labels: [Int: SpaceLabel] { stateStore.labels }
    public var displayOrder: [Int] { stateStore.displayOrder }
    public var usesCustomDisplayOrder: Bool { stateStore.usesCustomDisplayOrder }
    public var desktopNumberBySpaceID: [Int: Int] { stateStore.desktopNumberBySpaceID }
    public var nativeOrderByDisplay: [String: [Int]] { stateStore.nativeOrderByDisplay }

    private let cgsBridge: any CGSBridgeProtocol
    private let labelStore: SpaceLabelStore
    private let switcherService: SpaceSwitcherService
    private let stateStore: SpaceStateStore
    private let orderingService: SpaceOrderingService
    private var stateStoreObserver: AnyCancellable?
    private lazy var switchingCoordinator = makeSwitchingCoordinator()

    public init(
        store: SpaceStore = SpaceStore(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        labelStore: SpaceLabelStore? = nil,
        switcherService: SpaceSwitcherService? = nil
    ) {
        self.cgsBridge = cgsBridge
        self.labelStore = labelStore ?? SpaceLabelStore(store: store)
        self.switcherService = switcherService ?? SpaceSwitcherService(cgsBridge: cgsBridge)
        self.stateStore = SpaceStateStore()
        self.orderingService = SpaceOrderingService()
        self.stateStoreObserver = nil
        bindStateStore()
        syncPersistenceState()
        refreshSpaces()
        reconcilePersistedSpaces()
    }

    public func refreshSpaces() {
        apply(snapshot: cgsBridge.managedSnapshot())
    }

    public func refreshSpacesAsync() {
        switchingCoordinator.refreshSpacesAsync()
    }

    public func refreshSpacesSoon() {
        switchingCoordinator.refreshSpacesSoon()
    }

    public func handleSpaceChange() {
        let before = activeSpaceID
        refreshSpaces()
        if before != activeSpaceID {
            Logger.shared.info("space-change")
        }
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
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int) {
        labelStore.moveDisplayOrder(
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            currentOrderedSpaceIDs: orderedSpaceIDs()
        )
        syncPersistenceState()
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

    public func switchToSpace(_ spaceID: Int) -> SwitchResult {
        switchingCoordinator.switchToSpace(spaceID)
    }

    public func switchToNextSpace() {
        switchingCoordinator.switchToNextSpace()
    }

    public func switchToPreviousSpace() {
        switchingCoordinator.switchToPreviousSpace()
    }

    public func persistNow() {
        labelStore.persistNow(orderedSpaceIDs: orderedSpaceIDs())
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
        if spacesChanged {
            reconcilePersistedSpaces()
        }
    }

    private func reconcilePersistedSpaces() {
        labelStore.reconcileLabels(for: spaces, orderedSpaceIDs: orderedSpaceIDs())
        syncPersistenceState()
    }

    private func syncPersistenceState() {
        stateStore.syncPersistenceState(
            labels: labelStore.labels,
            displayOrder: labelStore.displayOrder,
            usesCustomDisplayOrder: labelStore.usesCustomDisplayOrder
        )
    }

    private func applyManagedSnapshot(_ snapshot: CGSBridge.ManagedSnapshot) {
        apply(snapshot: snapshot)
    }

    private func makeSwitchingCoordinator() -> SpaceSwitchingCoordinator {
        SpaceSwitchingCoordinator(
            cgsBridge: cgsBridge,
            stateStore: stateStore,
            switcherService: switcherService,
            orderedSpaceIDs: { [weak self] in
                self?.orderedSpaceIDs() ?? []
            },
            refreshNow: { [weak self] in
                self?.refreshSpaces()
            },
            applySnapshot: { [weak self] snapshot in
                self?.applyManagedSnapshot(snapshot)
            }
        )
    }
}
