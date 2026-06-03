import Foundation
import Combine
import AppKit

public final class SpaceRegistry: ObservableObject {
    @Published public private(set) var spaces: [SpaceIdentity] = []
    @Published public private(set) var activeSpaceID: Int?
    @Published public private(set) var labels: [Int: SpaceLabel] = [:]
    @Published public private(set) var displayOrder: [Int] = []
    @Published public private(set) var desktopNumberBySpaceID: [Int: Int] = [:]
    @Published public private(set) var nativeOrderByDisplay: [String: [Int]] = [:]

    private let store: SpaceStore
    private let persistQueue = DispatchQueue(label: "namedspaces.persist", qos: .utility)
    private let snapshotQueue = DispatchQueue(label: "namedspaces.snapshot", qos: .userInitiated)
    private var pendingPersist: DispatchWorkItem?
    private var pendingRefresh: DispatchWorkItem?
    private let refreshRetryInterval: TimeInterval = 0.05
    private let refreshRetryLimit = 8

    public init(store: SpaceStore = SpaceStore()) {
        self.store = store
        let persisted = store.load()
        self.labels = persisted.labels
        self.displayOrder = persisted.displayOrder
        refreshSpaces()
        reconcileUnknownSpaces()
    }

    public func refreshSpaces() {
        apply(snapshot: CGSBridge.managedSnapshot())
    }

    public func refreshSpacesAsync() {
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = CGSBridge.managedSnapshot()
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
        let global = CGSBridge.activeSpaceID()
        let selectedDisplay = displayForCurrentFocus(snapshot: snapshot, globalActiveID: global)
        let discovered = snapshot.spaces.filter { space in
            guard let selectedDisplay else { return true }
            return space.display == selectedDisplay
        }
        let nextSpaces = discovered.isEmpty ? fallbackSpaces() : discovered
        if nextSpaces != spaces {
            spaces = nextSpaces
            reconcileUnknownSpaces()
        }

        if snapshot.orderedIDsByDisplay != nativeOrderByDisplay {
            nativeOrderByDisplay = snapshot.orderedIDsByDisplay
            var numbers: [Int: Int] = [:]
            for order in snapshot.orderedIDsByDisplay.values {
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
            Logger.shared.info("space-change active=\(activeSpaceID ?? -1)")
        }
    }

    public func name(for spaceID: Int) -> String {
        labels[spaceID]?.name ?? "Unnamed space"
    }

    public func namespaceLabel(for spaceID: Int) -> String {
        guard let number = desktopNumberBySpaceID[spaceID] else { return "Desktop ?" }
        return "Desktop \(number)"
    }

    public func rename(spaceID: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "Unnamed space" : trimmed
        if labels[spaceID]?.name == normalized {
            return
        }
        var updated = labels
        updated[spaceID] = SpaceLabel(name: normalized)
        labels = updated
        persist()
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int) {
        var ids = orderedSpaceIDs()
        let removed = fromOffsets.compactMap { offset in
            ids.indices.contains(offset) ? ids[offset] : nil
        }
        for offset in fromOffsets.sorted(by: >) where ids.indices.contains(offset) {
            ids.remove(at: offset)
        }

        var insertionIndex = toOffset
        for offset in fromOffsets where offset < toOffset {
            insertionIndex -= 1
        }
        insertionIndex = max(0, min(insertionIndex, ids.count))
        ids.insert(contentsOf: removed, at: insertionIndex)
        displayOrder = ids
        persist()
    }

    public func orderedSpaceIDs() -> [Int] {
        var ids = displayOrder.filter { id in spaces.contains(where: { $0.id == id }) }
        for id in spaces.map(\.id) where !ids.contains(id) {
            ids.append(id)
        }
        return ids
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
        activeSpaceID.map { name(for: $0) } ?? "Unnamed space"
    }

    public func activeName() -> String {
        activeNameSummary()
    }

    public func switchToSpace(_ spaceID: Int) {
        let before = activeSpaceID
        if before == spaceID {
            Logger.shared.info("switch-space requested=\(spaceID) skipped=already-active")
            return
        }

        let snapshot = CGSBridge.managedSnapshot()
        guard let display = spaces.first(where: { $0.id == spaceID })?.display
            ?? snapshot.spaces.first(where: { $0.id == spaceID })?.display,
              let nativeOrder = nativeOrderByDisplay[display] ?? snapshot.orderedIDsByDisplay[display],
              let shortcutIndex = nativeOrder.firstIndex(of: spaceID).map({ $0 + 1 }) else {
            Logger.shared.error("switch-space requested=\(spaceID) failed=unknown-space")
            return
        }

        guard shortcutIndex <= 6 else {
            Logger.shared.error(
                "switch-space requested=\(spaceID) failed=desktop-\(shortcutIndex)-no-shortcut " +
                "(only Ctrl+1…6 are supported)"
            )
            return
        }

        let posted = CGSBridge.switchByDesktopShortcut(index: shortcutIndex)
        Logger.shared.info(
            "switch-space requested=\(spaceID) before=\(before ?? -1) " +
            "shortcutIndex=\(shortcutIndex) posted=\(posted)"
        )

        refreshSpacesSoon()
        Logger.shared.info(
            "switch-space result requested=\(spaceID) after=\(activeSpaceID ?? -1) matched=\(activeSpaceID == spaceID)"
        )
    }

    public func switchToNextSpace() {
        switchToAdjacentSpace(offset: 1)
    }

    public func switchToPreviousSpace() {
        switchToAdjacentSpace(offset: -1)
    }

    private func reconcileUnknownSpaces() {
        var updated = labels
        var changed = false
        for id in spaces.map(\.id) where updated[id] == nil {
            updated[id] = SpaceLabel(name: "Unnamed space")
            changed = true
        }
        let valid = Set(spaces.map(\.id))
        for key in updated.keys where !valid.contains(key) {
            updated.removeValue(forKey: key)
            changed = true
        }
        if changed {
            labels = updated
            persist()
        }
    }

    private func fallbackSpaces() -> [SpaceIdentity] {
        [SpaceIdentity(id: 1, display: "fallback-display")]
    }

    private func displayForCurrentFocus(snapshot: CGSBridge.ManagedSnapshot, globalActiveID: Int?) -> String? {
        if let globalActiveID,
           let display = snapshot.activeByDisplay.first(where: { $0.value == globalActiveID })?.key {
            return display
        }
        return snapshot.activeByDisplay.keys.sorted().first ?? snapshot.spaces.first?.display
    }

    private func persist() {
        let payload = PersistedSpaces(labels: labels, displayOrder: orderedSpaceIDs())
        pendingPersist?.cancel()
        let task = DispatchWorkItem { [store] in
            do {
                try store.save(payload)
            } catch {
                Logger.shared.error("persist-failed error=\(error.localizedDescription)")
            }
        }
        pendingPersist = task
        persistQueue.asyncAfter(deadline: .now() + 0.2, execute: task)
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
        switchToSpace(target)
    }

    public func persistNow() {
        pendingPersist?.cancel()
        let payload = PersistedSpaces(labels: labels, displayOrder: orderedSpaceIDs())
        do {
            try store.save(payload)
        } catch {
            Logger.shared.error("persist-failed error=\(error.localizedDescription)")
        }
    }
}
