import Foundation

public final class SpaceLabelStore {
    public private(set) var labels: [Int: SpaceLabel]
    public private(set) var displayOrder: [Int]
    public private(set) var usesCustomDisplayOrder: Bool

    private let store: SpaceStore
    private let persistQueue: DispatchQueue
    private let logger: any Logging
    private var pendingPersist: DispatchWorkItem?

    public init(
        store: SpaceStore = SpaceStore(),
        persistQueue: DispatchQueue = DispatchQueue(label: "stayhere.persist", qos: .utility),
        logger: any Logging
    ) {
        self.store = store
        self.persistQueue = persistQueue
        self.logger = logger

        let persisted = store.load()
        self.labels = persisted.labels
        self.displayOrder = persisted.displayOrder
        self.usesCustomDisplayOrder = persisted.usesCustomDisplayOrder
    }

    public func rename(spaceID: Int, name: String, orderedSpaceIDs: @autoclosure () -> [Int]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "Unnamed space" : trimmed
        if labels[spaceID]?.name == normalized {
            return
        }

        labels[spaceID] = SpaceLabel(name: normalized)
        persist(orderedSpaceIDs: orderedSpaceIDs())
    }

    public func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int, currentOrderedSpaceIDs: [Int]) {
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
        persist(orderedSpaceIDs: ids)
    }

    public func reconcileLabels(for spaces: [SpaceIdentity], orderedSpaceIDs: @autoclosure () -> [Int]) {
        var updated = labels
        var changed = false

        for id in spaces.map(\.id) where updated[id] == nil {
            updated[id] = SpaceLabel(name: "Unnamed space")
            changed = true
        }

        let validIDs = Set(spaces.map(\.id))
        for key in updated.keys where !validIDs.contains(key) {
            updated.removeValue(forKey: key)
            changed = true
        }

        guard changed else { return }

        labels = updated
        persist(orderedSpaceIDs: orderedSpaceIDs())
    }

    public func persistNow(orderedSpaceIDs: [Int]) {
        pendingPersist?.cancel()
        do {
            try store.save(
                PersistedSpaces(
                    labels: labels,
                    displayOrder: orderedSpaceIDs,
                    usesCustomDisplayOrder: usesCustomDisplayOrder
                )
            )
        } catch {
            logger.error("persist-failed")
        }
    }

    private func persist(orderedSpaceIDs: [Int]) {
        let payload = PersistedSpaces(
            labels: labels,
            displayOrder: orderedSpaceIDs,
            usesCustomDisplayOrder: usesCustomDisplayOrder
        )
        pendingPersist?.cancel()
        let task = DispatchWorkItem { [store, logger] in
            do {
                try store.save(payload)
            } catch {
                logger.error("persist-failed")
            }
        }
        pendingPersist = task
        persistQueue.asyncAfter(deadline: .now() + 0.2, execute: task)
    }
}
