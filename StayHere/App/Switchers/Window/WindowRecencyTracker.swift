import Foundation

final class WindowRecencyTracker {
    private(set) var recentWindowIDs: [Int] = []

    func orderedEntriesAndGroups(
        from spaceGroups: [SpaceWindowGroup],
        scope: WindowRecencyScope
    ) -> (entries: [WindowEntry], groups: [SpaceWindowGroup]) {
        let groups = recentEntries(from: spaceGroups, scope: scope)
        return (groups.flatMap(\.entries), groups)
    }

    func recordSelection(
        _ selectedWindowID: Int,
        in activeSession: (any WindowSwitcherSessionProtocol)?,
        scope: WindowRecencyScope
    ) {
        guard let activeSession else {
            // No-session commit is a pure promote-to-front, deliberately
            // scope-independent (preserves the recency tail for both scopes).
            recentWindowIDs.removeAll { $0 == selectedWindowID }
            recentWindowIDs.insert(selectedWindowID, at: 0)
            return
        }
        var promoting = [selectedWindowID]
        if let startingWindowID = activeSession.startingWindowID,
           startingWindowID != selectedWindowID {
            promoting.append(startingWindowID)
        }
        recentWindowIDs = RecencyOrdering.merge(
            recentIDs: recentWindowIDs,
            incomingIDs: activeSession.flatEntries.map(\.windowID),
            promoting: promoting,
            scope: scope
        )
    }

    func reset() {
        recentWindowIDs = []
    }

    func promoteToCurrent(_ windowID: Int) {
        if let index = recentWindowIDs.firstIndex(of: windowID) {
            let id = recentWindowIDs.remove(at: index)
            recentWindowIDs.insert(id, at: 0)
        }
    }

    private func recentEntries(
        from spaceGroups: [SpaceWindowGroup],
        scope: WindowRecencyScope
    ) -> [SpaceWindowGroup] {
        let allEntries = spaceGroups.flatMap(\.entries)
        let entriesByID = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.windowID, $0) })

        let mergedIDs = RecencyOrdering.merge(
            recentIDs: recentWindowIDs,
            incomingIDs: allEntries.map(\.windowID),
            scope: scope
        )
        recentWindowIDs = mergedIDs
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

        return sortedSpaceIDs.compactMap { spaceID in
            guard let sorted = recencyBySpaceID[spaceID], !sorted.isEmpty,
                  let original = spaceGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: sorted
            )
        }
    }
}
