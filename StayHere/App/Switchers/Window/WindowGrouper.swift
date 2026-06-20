import Foundation
import Core

final class WindowGrouper {
    private let orderedSpaceIDs: () -> [Int]
    private let spacesByID: () -> [Int: SpaceIdentity]
    private let spacesForWindow: (Int) -> [Int]
    private let nameProvider: (Int) -> String
    private let namespaceLabelProvider: (Int) -> String

    init(
        orderedSpaceIDs: @escaping () -> [Int],
        spacesByID: @escaping () -> [Int: SpaceIdentity],
        spacesForWindow: @escaping (Int) -> [Int],
        nameProvider: @escaping (Int) -> String,
        namespaceLabelProvider: @escaping (Int) -> String
    ) {
        self.orderedSpaceIDs = orderedSpaceIDs
        self.spacesByID = spacesByID
        self.spacesForWindow = spacesForWindow
        self.nameProvider = nameProvider
        self.namespaceLabelProvider = namespaceLabelProvider
    }

    func groupWindows(_ windows: [WindowEntry]) -> [WindowListProvider.SpaceWindowGroup] {
        let orderedIDs = orderedSpaceIDs()
        let spaces = spacesByID()
        var windowsBySpace: [Int: [WindowEntry]] = [:]

        for window in windows {
            let spaceIDs = spacesForWindow(window.windowID)
            if let primarySpaceID = spaceIDs.first(where: { orderedIDs.contains($0) })
                ?? spaceIDs.first {
                windowsBySpace[primarySpaceID, default: []].append(window)
            }
        }

        var groups: [WindowListProvider.SpaceWindowGroup] = []
        for spaceID in orderedIDs {
            guard let entries = windowsBySpace[spaceID], !entries.isEmpty else { continue }
            let space = spaces[spaceID]
            let label = nameProvider(spaceID)
            let systemName = space?.systemName
            let displayLabel: String
            if label != "Unnamed space" {
                displayLabel = label
            } else if let systemName, !systemName.isEmpty {
                displayLabel = systemName
            } else {
                displayLabel = namespaceLabelProvider(spaceID)
            }
            groups.append(WindowListProvider.SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: displayLabel,
                entries: entries
            ))
        }

        return groups
    }
}
