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

    /// Stores the per-space entries, unless the result is stale.
    /// - Returns: `true` if accepted; `false` if the result belongs to a refresh
    ///   dispatched before an `invalidate()` (generation mismatch) and was
    ///   discarded — callers should re-dispatch a refresh so self-heal is
    ///   guaranteed rather than best-effort (ARCH-1 / CORR-4).
    @discardableResult
    func updatePerSpace(with entries: [WindowEntry], context: WindowSpaceContext, generation: Int) -> Bool {
        guard generation == cacheGeneration else { return false }
        cachedEntriesContext = context
        cachedEntries = entries
        return true
    }

    func allSpacesHit() -> [SpaceWindowGroup]? {
        cachedAllSpacesEntries
    }

    /// Stores the all-spaces groups, unless the result is stale.
    /// - Returns: `true` if accepted; `false` if the result belongs to a refresh
    ///   dispatched before an `invalidate()` (generation mismatch) and was
    ///   discarded — callers should re-dispatch a refresh so self-heal is
    ///   guaranteed rather than best-effort (ARCH-1).
    @discardableResult
    func updateAllSpaces(with groups: [SpaceWindowGroup], generation: Int) -> Bool {
        guard generation == cacheGeneration else { return false }
        cachedAllSpacesEntries = groups
        return true
    }

    func invalidate() {
        cacheGeneration += 1
        cachedEntriesContext = nil
        cachedEntries = nil
        cachedAllSpacesEntries = nil
    }
}
