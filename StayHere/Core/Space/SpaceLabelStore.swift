import Foundation

public final class SpaceLabelStore: @unchecked Sendable {
    public private(set) var labels: [Int: SpaceLabel]
    public private(set) var displayOrder: [Int]
    public private(set) var usesCustomDisplayOrder: Bool

    private let store: SpaceStore
    private let logger: any Logging
    private var pendingPersistTask: Task<Void, Never>?
    private let lock = NSLock()

    public init(
        store: SpaceStore = SpaceStore(),
        logger: any Logging
    ) {
        self.store = store
        self.logger = logger

        let persisted = store.load()
        self.labels = persisted.labels
        self.displayOrder = persisted.displayOrder
        self.usesCustomDisplayOrder = persisted.usesCustomDisplayOrder
    }

    public func rename(spaceID: Int, name: String, orderedSpaceIDs: @autoclosure () -> [Int]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? SpaceDisplayNameProvider.defaultUnnamedName : trimmed

        lock.lock()
        defer { lock.unlock() }

        if labels[spaceID]?.name == normalized {
            return
        }

        labels[spaceID] = SpaceLabel(name: normalized)
        persistDebounced(
            orderedSpaceIDs: orderedSpaceIDs(),
            labels: labels,
            usesCustomDisplayOrder: usesCustomDisplayOrder
        )
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int, currentOrderedSpaceIDs: [Int]) {
        lock.lock()
        var ids = currentOrderedSpaceIDs
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
        usesCustomDisplayOrder = true
        persistDebounced(
            orderedSpaceIDs: ids,
            labels: labels,
            usesCustomDisplayOrder: usesCustomDisplayOrder
        )
        lock.unlock()
    }

    public func reconcileLabels(for spaces: [SpaceIdentity], orderedSpaceIDs: @autoclosure () -> [Int]) {
        lock.lock()
        var updated = labels
        var changed = false

        for id in spaces.map(\.id) where updated[id] == nil {
            updated[id] = SpaceLabel(name: SpaceDisplayNameProvider.defaultUnnamedName)
            changed = true
        }

        let validIDs = Set(spaces.map(\.id))
        for key in updated.keys where !validIDs.contains(key) {
            updated.removeValue(forKey: key)
            changed = true
        }

        guard changed else {
            lock.unlock()
            return
        }

        labels = updated
        persistDebounced(
            orderedSpaceIDs: orderedSpaceIDs(),
            labels: labels,
            usesCustomDisplayOrder: usesCustomDisplayOrder
        )
        lock.unlock()
    }

    public func persistNow(orderedSpaceIDs: [Int]) {
        lock.lock()
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        let currentLabels = labels
        let currentUsesCustomDisplayOrder = usesCustomDisplayOrder
        lock.unlock()

        do {
            try store.save(
                PersistedSpaces(
                    labels: currentLabels,
                    displayOrder: orderedSpaceIDs,
                    usesCustomDisplayOrder: currentUsesCustomDisplayOrder
                )
            )
        } catch {
            logger.error("persist-failed")
        }
    }

    /// Returns a consistent snapshot of all persistence-related state,
    /// acquired under the lock so callers can read without racing mutations.
    func persistenceSnapshot() -> (labels: [Int: SpaceLabel], displayOrder: [Int], usesCustomDisplayOrder: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (labels, displayOrder, usesCustomDisplayOrder)
    }

    private func persistDebounced(
        orderedSpaceIDs: [Int],
        labels labelsSnapshot: [Int: SpaceLabel],
        usesCustomDisplayOrder usesCustomSnapshot: Bool
    ) {
        pendingPersistTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s debounce
            guard !Task.isCancelled else { return }

            do {
                try self.store.save(
                    PersistedSpaces(
                        labels: labelsSnapshot,
                        displayOrder: orderedSpaceIDs,
                        usesCustomDisplayOrder: usesCustomSnapshot
                    )
                )
            } catch {
                self.logger.error("persist-failed")
            }
        }
        pendingPersistTask = task
    }
}
