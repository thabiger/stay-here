import Foundation

/// Shared MRU state for both switchers (see CompositionControllers.swift).
///
/// The query `orderedEntriesAndGroups` is read-only: it returns the desired
/// persistent order (`mergedOrder`) without writing. State is mutated at
/// exactly two lifecycle points — `apply(order:)` once per session build
/// (listing path, from `WindowSwitcherController.buildSession`) and
/// `recordSelection` at commit — plus `reset()`. The stored array is capped
/// at `recentWindowIDsLimit`: with the all-spaces switcher disabled only
/// `.subset` merges occur, which preserve stale IDs by design, so without
/// the cap the array would grow unboundedly.
final class WindowRecencyTracker {
    private static let recentWindowIDsLimit = 512

    private(set) var recentWindowIDs: [Int] = []

    /// Pure read query. Orders `spaceGroups` by recency and returns the
    /// entries, the regrouped spaces, and the full desired persistent order
    /// (`mergedOrder`, including the `.subset`-preserved tail). Does not
    /// mutate state — callers apply the order via `apply(order:)`.
    func orderedEntriesAndGroups(
        from spaceGroups: [SpaceWindowGroup],
        scope: WindowRecencyScope
    ) -> (entries: [WindowEntry], groups: [SpaceWindowGroup], mergedOrder: [Int]) {
        let (groups, mergedOrder) = recentEntries(from: spaceGroups, scope: scope)
        return (groups.flatMap(\.entries), groups, mergedOrder)
    }

    /// Listing-path mutation; called once per session build by the
    /// controller. Stores `order`, capped at `recentWindowIDsLimit`.
    func apply(order: [Int]) {
        store(order)
    }

    func recordSelection(
        _ selectedWindowID: Int,
        in activeSession: (any WindowSwitcherSessionProtocol)?,
        scope: WindowRecencyScope
    ) {
        guard let activeSession else {
            // No-session commit is a pure promote-to-front, deliberately
            // scope-independent (preserves the recency tail for both scopes).
            var updated = recentWindowIDs
            updated.removeAll { $0 == selectedWindowID }
            updated.insert(selectedWindowID, at: 0)
            store(updated)
            return
        }
        var promoting = [selectedWindowID]
        if let startingWindowID = activeSession.startingWindowID,
           startingWindowID != selectedWindowID {
            promoting.append(startingWindowID)
        }
        store(RecencyOrdering.merge(
            recentIDs: recentWindowIDs,
            incomingIDs: activeSession.flatEntries.map(\.windowID),
            promoting: promoting,
            scope: scope
        ))
    }

    func reset() {
        recentWindowIDs = []
    }

    private func store(_ ids: [Int]) {
        recentWindowIDs = Array(ids.prefix(Self.recentWindowIDsLimit))
    }

    /// An entry paired with the space it came from. Carrying the spaceID
    /// alongside the entry means regrouping never needs a fallback space
    /// lookup — the previous `windowSpaceLookup[entry.windowID] ?? -1`
    /// sentinel was dead (every entry in the ordered list originates from
    /// `spaceGroups`) and could silently produce phantom space groups.
    struct SpaceEntry {
        let spaceID: Int
        let entry: WindowEntry
    }

    /// Pure regrouping step: given the recency-ordered flat entries and the
    /// original space groups, returns the same entries regrouped per space —
    /// each space's entries in recency order, spaces ordered by their most
    /// recent entry. Spaces with no surviving entries (or no matching source
    /// group) are dropped. Does not read or write `recentWindowIDs`.
    static func groupedBySpace(
        ordered: [SpaceEntry],
        from spaceGroups: [SpaceWindowGroup]
    ) -> [SpaceWindowGroup] {
        let orderIndex = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element.entry.windowID, $0.offset) }
        )
        let grouped = Dictionary(grouping: ordered, by: \.spaceID)

        let sortedSpaceIDs = grouped.keys.sorted { a, b in
            let aIndex = grouped[a]?.first.flatMap { orderIndex[$0.entry.windowID] } ?? Int.max
            let bIndex = grouped[b]?.first.flatMap { orderIndex[$0.entry.windowID] } ?? Int.max
            return aIndex < bIndex
        }

        return sortedSpaceIDs.compactMap { spaceID in
            guard let spaceEntries = grouped[spaceID], !spaceEntries.isEmpty,
                  let original = spaceGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: spaceEntries.map(\.entry)
            )
        }
    }

    private func recentEntries(
        from spaceGroups: [SpaceWindowGroup],
        scope: WindowRecencyScope
    ) -> ([SpaceWindowGroup], [Int]) {
        let allEntries = spaceGroups.flatMap(\.entries)
        // Each entry carries the space it came from, so regrouping never
        // performs a lookup that could fall back to a sentinel space ID.
        let spaceEntryByID = Dictionary(
            uniqueKeysWithValues: spaceGroups.flatMap { group in
                group.entries.map { SpaceEntry(spaceID: group.spaceID, entry: $0) }
            }.map { ($0.entry.windowID, $0) }
        )

        let mergedIDs = RecencyOrdering.merge(
            recentIDs: recentWindowIDs,
            incomingIDs: allEntries.map(\.windowID),
            scope: scope
        )
        let groups = Self.groupedBySpace(
            ordered: mergedIDs.compactMap { spaceEntryByID[$0] },
            from: spaceGroups
        )
        return (groups, mergedIDs)
    }
}
