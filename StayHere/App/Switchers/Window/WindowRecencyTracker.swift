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

    private func recentEntries(
        from spaceGroups: [SpaceWindowGroup],
        scope: WindowRecencyScope
    ) -> ([SpaceWindowGroup], [Int]) {
        let allEntries = spaceGroups.flatMap(\.entries)
        let entriesByID = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.windowID, $0) })

        let mergedIDs = RecencyOrdering.merge(
            recentIDs: recentWindowIDs,
            incomingIDs: allEntries.map(\.windowID),
            scope: scope
        )
        let orderedFlat = mergedIDs.compactMap { entriesByID[$0] }

        var windowSpaceLookup: [Int: Int] = [:]
        for group in spaceGroups {
            for entry in group.entries {
                windowSpaceLookup[entry.windowID] = group.spaceID
            }
        }

        let recencyBySpaceID: [Int: [WindowEntry]] = Dictionary(
            grouping: orderedFlat,
            by: { entry in
                windowSpaceLookup[entry.windowID] ?? -1
            }
        )

        let windowIndexLookup: [Int: Int] = Dictionary(
            uniqueKeysWithValues: orderedFlat.enumerated().map { ($0.element.windowID, $0.offset) }
        )

        let sortedSpaceIDs = recencyBySpaceID.keys.sorted { a, b in
            let aIndex = (recencyBySpaceID[a]?.first).flatMap { first in
                windowIndexLookup[first.windowID]
            } ?? Int.max
            let bIndex = (recencyBySpaceID[b]?.first).flatMap { first in
                windowIndexLookup[first.windowID]
            } ?? Int.max
            return aIndex < bIndex
        }

        let groups: [SpaceWindowGroup] = sortedSpaceIDs.compactMap { spaceID in
            guard let sorted = recencyBySpaceID[spaceID], !sorted.isEmpty,
                  let original = spaceGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: sorted
            )
        }
        return (groups, mergedIDs)
    }
}
