import Foundation

final class WindowRecencyTracker {
    private(set) var recentWindowIDs: [Int] = []

    func orderedEntriesAndGroups(
        from spaceGroups: [WindowListProvider.SpaceWindowGroup]
    ) -> (entries: [WindowEntry], groups: [WindowListProvider.SpaceWindowGroup]) {
        let groups = recentEntries(from: spaceGroups)
        return (groups.flatMap(\.entries), groups)
    }

    func recordSelection(
        _ selectedWindowID: Int,
        in activeSession: (any WindowSwitcherSessionProtocol)?
    ) {
        WindowSwitcherSelection.recordSelection(
            selectedWindowID,
            in: activeSession,
            recentWindowIDs: &recentWindowIDs
        )
    }

    func reset() {
        recentWindowIDs = []
    }

    private func recentEntries(from spaceGroups: [WindowListProvider.SpaceWindowGroup]) -> [WindowListProvider.SpaceWindowGroup] {
        let allEntries = spaceGroups.flatMap(\.entries)
        guard !allEntries.isEmpty else {
            recentWindowIDs = []
            return []
        }

        let entryIDs = Set(allEntries.map(\.windowID))
        let orderedIDs = recentWindowIDs.filter { entryIDs.contains($0) }

        let knownIDs = Set(orderedIDs)
        let unknownEntries = allEntries.filter { !knownIDs.contains($0.windowID) }
        let entriesByID = Dictionary(uniqueKeysWithValues: allEntries.map { ($0.windowID, $0) })
        let orderedFlat = orderedIDs.compactMap { entriesByID[$0] } + unknownEntries
        recentWindowIDs = orderedFlat.map(\.windowID)

        let recencyBySpaceID: [Int: [WindowEntry]] = Dictionary(
            grouping: orderedFlat,
            by: { entry in
                spaceGroups.first(where: { group in
                    group.entries.contains(where: { $0.windowID == entry.windowID })
                })?.spaceID ?? -1
            }
        )

        let sortedSpaceIDs = recencyBySpaceID.keys.sorted { a, b in
            let aIndex = (recencyBySpaceID[a]?.first).flatMap { first in
                orderedFlat.firstIndex(where: { $0.windowID == first.windowID })
            } ?? Int.max
            let bIndex = (recencyBySpaceID[b]?.first).flatMap { first in
                orderedFlat.firstIndex(where: { $0.windowID == first.windowID })
            } ?? Int.max
            return aIndex < bIndex
        }

        return sortedSpaceIDs.compactMap { spaceID in
            guard let sorted = recencyBySpaceID[spaceID], !sorted.isEmpty,
                  let original = spaceGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return WindowListProvider.SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: sorted
            )
        }
    }
}
