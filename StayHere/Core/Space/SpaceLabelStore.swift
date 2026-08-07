import Foundation

@MainActor
public final class SpaceLabelStore {
    public private(set) var labels: [Int: SpaceLabel]

    private let store: SpaceStore
    private let logger: any Logging
    private var pendingPersistTask: Task<Void, Never>?

    public init(
        store: SpaceStore = SpaceStore(),
        logger: any Logging
    ) {
        self.store = store
        self.logger = logger

        let persisted = store.load()
        self.labels = persisted.labels
    }

    public func rename(spaceID: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? SpaceDisplayNameProvider.defaultUnnamedName : trimmed

        if labels[spaceID]?.name == normalized {
            return
        }

        labels[spaceID] = SpaceLabel(name: normalized)
        persistDebounced(labels: labels)
    }

    public func reconcileLabels(for spaces: [SpaceIdentity]) {
        guard !spaces.isEmpty else { return }

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

        guard changed else { return }

        labels = updated
        persistDebounced(labels: labels)
    }

    public func persistNow() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil

        do {
            try store.save(PersistedSpaces(labels: labels))
        } catch {
            logger.error("persist-failed")
        }
    }

    func persistenceSnapshot() -> [Int: SpaceLabel] {
        labels
    }

    private func persistDebounced(
        labels labelsSnapshot: [Int: SpaceLabel]
    ) {
        pendingPersistTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s debounce
            guard !Task.isCancelled else { return }

            do {
                try self.store.save(PersistedSpaces(labels: labelsSnapshot))
            } catch {
                self.logger.error("persist-failed")
            }
        }
        pendingPersistTask = task
    }
}
