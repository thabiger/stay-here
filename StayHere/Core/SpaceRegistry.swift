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

    @Published public private(set) var spaces: [SpaceIdentity] = []
    @Published public private(set) var activeSpaceID: Int?
    @Published public private(set) var labels: [Int: SpaceLabel] = [:]
    @Published public private(set) var displayOrder: [Int] = []
    @Published public private(set) var usesCustomDisplayOrder: Bool = false
    @Published public private(set) var desktopNumberBySpaceID: [Int: Int] = [:]
    @Published public private(set) var nativeOrderByDisplay: [String: [Int]] = [:]

    private let cgsBridge: any CGSBridgeProtocol
    private let labelStore: SpaceLabelStore
    private let switcherService: SpaceSwitcherService
    private let snapshotQueue = DispatchQueue(label: "stayhere.snapshot", qos: .userInitiated)
    private var pendingRefresh: DispatchWorkItem?
    private let refreshRetryInterval: TimeInterval = 0.05
    private let refreshRetryLimit = 8

    public init(
        store: SpaceStore = SpaceStore(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        labelStore: SpaceLabelStore? = nil,
        switcherService: SpaceSwitcherService? = nil
    ) {
        self.cgsBridge = cgsBridge
        self.labelStore = labelStore ?? SpaceLabelStore(store: store)
        self.switcherService = switcherService ?? SpaceSwitcherService(cgsBridge: cgsBridge)
        syncPersistenceState()
        refreshSpaces()
        reconcilePersistedSpaces()
    }

    public func refreshSpaces() {
        apply(snapshot: cgsBridge.managedSnapshot())
    }

    public func refreshSpacesAsync() {
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.cgsBridge.managedSnapshot()
            DispatchQueue.main.async {
                self.apply(snapshot: snapshot)
            }
        }
    }

    public func refreshSpacesSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        let baseline = activeSpaceID
        refreshSpaces()
        guard activeSpaceID == baseline else { return }
        scheduleRefreshRetry(baseline: baseline, remainingAttempts: refreshRetryLimit)
    }

    private func apply(snapshot: CGSBridge.ManagedSnapshot) {
        let global = cgsBridge.activeSpaceID()
        let selectedDisplay = displayForCurrentFocus(snapshot: snapshot, globalActiveID: global)
        let discovered = snapshot.spaces.filter { space in
            guard let selectedDisplay else { return true }
            return space.display == selectedDisplay
        }
        let nextSpaces = discovered.isEmpty ? fallbackSpaces() : discovered
        if nextSpaces != spaces {
            spaces = nextSpaces
            reconcilePersistedSpaces()
        }

        let desktopNativeOrder = snapshot.orderedIDsByDisplay.mapValues { order in
            order.filter { spaceID in
                snapshot.spaces.first(where: { $0.id == spaceID })?.kind == .desktop
            }
        }

        if desktopNativeOrder != nativeOrderByDisplay {
            nativeOrderByDisplay = desktopNativeOrder
            var numbers: [Int: Int] = [:]
            for order in desktopNativeOrder.values {
                for (idx, spaceID) in order.enumerated() {
                    numbers[spaceID] = idx + 1
                }
            }
            desktopNumberBySpaceID = numbers
        }

        let firstKnown = selectedDisplay.flatMap { snapshot.activeByDisplay[$0] } ?? snapshot.activeByDisplay.values.first
        let nextActive = global ?? firstKnown ?? activeSpaceID ?? nextSpaces.first?.id
        if nextActive != activeSpaceID {
            activeSpaceID = nextActive
        }
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
        switch space(for: spaceID)?.kind {
        case .desktop:
            guard let number = desktopNumberBySpaceID[spaceID] else { return "Desktop ?" }
            return "Desktop \(number)"
        case .fullscreen:
            return "Full Screen"
        case .unknown, .none:
            return "Space"
        }
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
        let desktopOrderedIDs = spaces
            .sorted { desktopSortKey(for: $0.id) < desktopSortKey(for: $1.id) }
            .map(\.id)

        guard usesCustomDisplayOrder else {
            return desktopOrderedIDs
        }

        let validIDs = Set(spaces.map(\.id))
        var ids = displayOrder.filter { validIDs.contains($0) }
        for id in desktopOrderedIDs where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    public func switchableOrderedSpaceIDs() -> [Int] {
        orderedSpaceIDs().filter(isSwitchableSpace)
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
        switcherService.switchToSpace(
            spaceID,
            snapshot: currentSwitchSnapshot(),
            refreshSpaces: { [weak self] in
                guard let self else {
                    return SpaceSwitchSnapshot(activeSpaceID: nil, spaces: [], nativeOrderByDisplay: [:])
                }
                self.refreshSpaces()
                return self.currentSwitchSnapshot()
            },
            scheduleRefreshSoon: { [weak self] in
                self?.refreshSpacesSoon()
            }
        )
    }

    public func switchToNextSpace() {
        switchToAdjacentSpace(offset: 1)
    }

    public func switchToPreviousSpace() {
        switchToAdjacentSpace(offset: -1)
    }

    private func reconcilePersistedSpaces() {
        labelStore.reconcileLabels(for: spaces, orderedSpaceIDs: orderedSpaceIDs())
        syncPersistenceState()
    }

    private func fallbackSpaces() -> [SpaceIdentity] {
        [SpaceIdentity(id: 1, display: "fallback-display")]
    }

    private func desktopSortKey(for spaceID: Int) -> (Int, Int) {
        (desktopNumberBySpaceID[spaceID] ?? Int.max, spaceID)
    }

    private func displayForCurrentFocus(snapshot: CGSBridge.ManagedSnapshot, globalActiveID: Int?) -> String? {
        if let globalActiveID,
           let display = snapshot.activeByDisplay.first(where: { $0.value == globalActiveID })?.key {
            return display
        }
        return snapshot.activeByDisplay.keys.sorted().first ?? snapshot.spaces.first?.display
    }

    private func scheduleRefreshRetry(baseline: Int?, remainingAttempts: Int) {
        pendingRefresh?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshSpaces()
            self.pendingRefresh = nil
            guard self.activeSpaceID == baseline, remainingAttempts > 1 else { return }
            self.scheduleRefreshRetry(baseline: baseline, remainingAttempts: remainingAttempts - 1)
        }
        pendingRefresh = task
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshRetryInterval, execute: task)
    }

    private func switchToAdjacentSpace(offset: Int) {
        let ordered = orderedSpaceIDs()
        let target = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: activeSpaceID, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: activeSpaceID, orderedSpaceIDs: ordered)
        guard let target else {
            Logger.shared.info("switch-space cycle skipped=empty")
            return
        }
        _ = switchToSpace(target)
    }

    public func persistNow() {
        labelStore.persistNow(orderedSpaceIDs: orderedSpaceIDs())
    }

    private func currentSwitchSnapshot() -> SpaceSwitchSnapshot {
        SpaceSwitchSnapshot(
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            nativeOrderByDisplay: nativeOrderByDisplay
        )
    }

    private func syncPersistenceState() {
        labels = labelStore.labels
        displayOrder = labelStore.displayOrder
        usesCustomDisplayOrder = labelStore.usesCustomDisplayOrder
    }
}
