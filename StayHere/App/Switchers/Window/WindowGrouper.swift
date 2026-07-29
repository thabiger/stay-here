import Foundation
import Core

/// Non-isolated grouping logic shared by `WindowGrouper` (main-actor path) and
/// `AllSpacesWindowComputer` (off-main background refresh path).
enum WindowSpaceGrouping {
    static func groupWindows(
        _ windows: [WindowEntry],
        orderedSpaceIDs: [Int],
        spacesByID: [Int: SpaceIdentity],
        spacesForWindow: (Int) -> [Int],
        nameProvider: (Int) -> String,
        namespaceLabelProvider: (Int) -> String
    ) -> [SpaceWindowGroup] {
        var windowsBySpace: [Int: [WindowEntry]] = [:]

        for window in windows {
            let spaceIDs = spacesForWindow(window.windowID)
            if let primarySpaceID = spaceIDs.first(where: { orderedSpaceIDs.contains($0) })
                ?? spaceIDs.first {
                windowsBySpace[primarySpaceID, default: []].append(window)
            }
        }

        var groups: [SpaceWindowGroup] = []
        for spaceID in orderedSpaceIDs {
            guard let entries = windowsBySpace[spaceID], !entries.isEmpty else { continue }
            let space = spacesByID[spaceID]
            let label = nameProvider(spaceID)
            let systemName = space?.systemName
            let displayLabel: String
            if label != SpaceDisplayNameProvider.defaultUnnamedName {
                displayLabel = label
            } else if let systemName, !systemName.isEmpty {
                displayLabel = systemName
            } else {
                displayLabel = namespaceLabelProvider(spaceID)
            }
            groups.append(SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: displayLabel,
                entries: entries
            ))
        }

        return groups
    }
}

@MainActor
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

    func groupWindows(_ windows: [WindowEntry]) -> [SpaceWindowGroup] {
        WindowSpaceGrouping.groupWindows(
            windows,
            orderedSpaceIDs: orderedSpaceIDs(),
            spacesByID: spacesByID(),
            spacesForWindow: spacesForWindow,
            nameProvider: nameProvider,
            namespaceLabelProvider: namespaceLabelProvider
        )
    }
}
