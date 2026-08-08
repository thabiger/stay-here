import Core

@MainActor
final class WindowListCache {
    private var cachedEntriesContext: WindowSpaceContext?
    private var cachedEntries: [WindowEntry]?
    private var cachedAllSpacesEntries: [SpaceWindowGroup]?

    /// Incremented on each `invalidate()` call. Captured at refresh-start time
    /// so background refresh results are discarded if the cache was invalidated
    /// while the task was in flight.
    private(set) var cacheGeneration = 0

    func perSpaceHit(for context: WindowSpaceContext) -> [WindowEntry]? {
        guard cachedEntriesContext == context, let cached = cachedEntries else { return nil }
        return cached
    }

    func updatePerSpace(with entries: [WindowEntry], context: WindowSpaceContext, generation: Int) {
        guard generation == cacheGeneration else { return }
        cachedEntriesContext = context
        cachedEntries = entries
    }

    func allSpacesHit() -> [SpaceWindowGroup]? {
        cachedAllSpacesEntries
    }

    func updateAllSpaces(with groups: [SpaceWindowGroup], generation: Int) {
        guard generation == cacheGeneration else { return }
        cachedAllSpacesEntries = groups
    }

    func invalidate() {
        cacheGeneration += 1
        cachedEntriesContext = nil
        cachedEntries = nil
        cachedAllSpacesEntries = nil
    }
}
