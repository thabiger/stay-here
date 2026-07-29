import Core

@MainActor
final class WindowListCache {
    private var cachedEntriesContext: WindowSpaceContext?
    private var cachedEntries: [WindowEntry]?
    private var cachedAllSpacesEntries: [SpaceWindowGroup]?

    func perSpaceHit(for context: WindowSpaceContext) -> [WindowEntry]? {
        guard cachedEntriesContext == context, let cached = cachedEntries else { return nil }
        return cached
    }

    func updatePerSpace(with entries: [WindowEntry], context: WindowSpaceContext) {
        cachedEntriesContext = context
        cachedEntries = entries
    }

    func allSpacesHit() -> [SpaceWindowGroup]? {
        cachedAllSpacesEntries
    }

    func updateAllSpaces(with groups: [SpaceWindowGroup]) {
        cachedAllSpacesEntries = groups
    }

    func invalidate() {
        cachedEntriesContext = nil
        cachedEntries = nil
        cachedAllSpacesEntries = nil
    }
}
