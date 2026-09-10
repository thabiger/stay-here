import AppKit
import Core

struct WindowSwitcherSessionSource {
    let spaceGroups: [SpaceWindowGroup]
    let flatEntries: [WindowEntry]
    let startingWindowID: Int?
    /// Desired persistent recency order after this session build (merged
    /// order + focus promotion). Applied once by
    /// WindowSwitcherController.buildSession. Unused on the snapshot path.
    let recencyOrder: [Int]
}

@MainActor
final class WindowListBuilder {
    private let mode: WindowSwitcherMode
    private let listProvider: WindowListProvider
    private let recencyTracker: WindowRecencyTracker
    private let registry: any SpaceRegistryProtocol
    private let settings: WindowSwitcherSettings

    init(
        mode: WindowSwitcherMode,
        listProvider: WindowListProvider,
        recencyTracker: WindowRecencyTracker,
        registry: any SpaceRegistryProtocol,
        settings: WindowSwitcherSettings
    ) {
        self.mode = mode
        self.listProvider = listProvider
        self.recencyTracker = recencyTracker
        self.registry = registry
        self.settings = settings
    }

    /// Focus promotion on open is deliberate (CORR-1 behavior); it is
    /// computed here purely and applied by the controller at session build —
    /// no state writes happen inside the builder.
    func makeSessionSource() -> WindowSwitcherSessionSource? {
        guard let spaceGroups = fetchSpaceGroups() else { return nil }

        switch mode {
        case .currentSpace:
            break
        case .allSpaces:
            let allEntries = spaceGroups.flatMap(\.entries)
            guard !allEntries.isEmpty else { return nil }
        }

        let (recencyEntries, recencyGroups, mergedOrder) = recencyTracker.orderedEntriesAndGroups(
            from: spaceGroups,
            scope: mode.recencyScope
        )

        var adjustedEntries = recencyEntries
        var recencyOrder = mergedOrder
        if let focusedID = listProvider.focusedWindowID(),
           let focusedIndex = adjustedEntries.firstIndex(where: { $0.windowID == focusedID }) {
            let focused = adjustedEntries.remove(at: focusedIndex)
            adjustedEntries.insert(focused, at: 0)
            if let recencyIndex = recencyOrder.firstIndex(of: focusedID) {
                let promoted = recencyOrder.remove(at: recencyIndex)
                recencyOrder.insert(promoted, at: 0)
            }
        }

        let sessionOrdered = Self.sessionOrder(fromRecentEntries: adjustedEntries)

        let finalGroups: [SpaceWindowGroup]
        if mode == .currentSpace, recencyGroups.isEmpty, spaceGroups.count == 1 {
            finalGroups = spaceGroups
        } else {
            finalGroups = Self.spaceGroups(from: sessionOrdered, using: recencyGroups)
        }

        return WindowSwitcherSessionSource(
            spaceGroups: finalGroups,
            flatEntries: sessionOrdered,
            startingWindowID: recencyEntries.first?.windowID,
            recencyOrder: recencyOrder
        )
    }

    func buildSnapshot(for session: (any WindowSwitcherSessionProtocol)?) -> WindowSwitcherSnapshot {
        let source: WindowSwitcherSessionSource
        if let session {
            source = WindowSwitcherSessionSource(
                spaceGroups: session.spaceGroups,
                flatEntries: session.flatEntries,
                startingWindowID: session.startingWindowID,
                recencyOrder: [] // unused on snapshot path — no state write
            )
        } else {
            guard let built = makeSessionSource() else { return emptySnapshot() }
            source = built
        }

        let selectedID = session?.selectedWindowID ?? source.flatEntries.first?.windowID

        let viewGroups: [WindowSwitcherSpaceGroup] = source.spaceGroups.map { group in
            let items = group.entries.map { entry in
                WindowSwitcherItem(
                    id: entry.windowID,
                    icon: entry.icon,
                    title: displayTitle(for: entry),
                    entry: entry,
                    isSelected: entry.windowID == selectedID
                )
            }
            return WindowSwitcherSpaceGroup(
                id: group.spaceID,
                spaceLabel: group.spaceLabel,
                items: items
            )
        }

        let totalWindows = viewGroups.reduce(0) { $0 + $1.items.count }

        switch mode {
        case .currentSpace:
            let spaceLabel = viewGroups.first?.spaceLabel ?? ""
            let subtitle = "\(totalWindows) windows on this Space"
            return WindowSwitcherSnapshot(
                spaceGroups: viewGroups,
                title: "\(spaceLabel)",
                subtitle: subtitle,
                emptyMessage: "No windows on this Space",
                iconName: "macwindow",
                showSpaceLabels: false
            )
        case .allSpaces:
            return WindowSwitcherSnapshot(
                spaceGroups: viewGroups,
                title: "All Spaces Window Switcher",
                subtitle: "\(totalWindows) windows across \(viewGroups.count) spaces",
                emptyMessage: "No windows across any Space",
                iconName: "rectangle.3.group",
                showSpaceLabels: true
            )
        }
    }

    func displayTitle(for entry: WindowEntry) -> String {
        WindowSwitcherTitleFormat.displayTitle(
            appName: entry.appName,
            windowTitle: entry.windowTitle,
            format: settings.windowSwitcherTitleFormat
        )
    }

    private func fetchSpaceGroups() -> [SpaceWindowGroup]? {
        switch mode {
        case .currentSpace:
            guard let context = listProvider.currentContext() else { return nil }
            let entries = listProvider.entries(in: context)
            let label = registry.name(for: context.spaceID)
            return [SpaceWindowGroup(
                spaceID: context.spaceID,
                spaceLabel: label,
                entries: entries
            )]
        case .allSpaces:
            return listProvider.entriesForAllSpaces()
        }
    }

    private func emptySnapshot() -> WindowSwitcherSnapshot {
        switch mode {
        case .currentSpace:
            return WindowSwitcherSnapshot(
                spaceGroups: [],
                title: "Window Switcher",
                subtitle: "0 windows",
                emptyMessage: "No windows on this Space",
                iconName: "macwindow",
                showSpaceLabels: false
            )
        case .allSpaces:
            return WindowSwitcherSnapshot(
                spaceGroups: [],
                title: "All Spaces Window Switcher",
                subtitle: "0 windows across 0 spaces",
                emptyMessage: "No windows across any Space",
                iconName: "rectangle.3.group",
                showSpaceLabels: true
            )
        }
    }

    private static func sessionOrder(fromRecentEntries entries: [WindowEntry]) -> [WindowEntry] {
        guard entries.count > 1 else { return entries }
        return [entries[1], entries[0]] + Array(entries.dropFirst(2))
    }

    private static func spaceGroups(
        from orderedEntries: [WindowEntry],
        using sortedGroups: [SpaceWindowGroup]
    ) -> [SpaceWindowGroup] {
        var entriesBySpace: [Int: [WindowEntry]] = [:]
        var spaceOrder: [Int] = []
        var seenSpaces: Set<Int> = []

        var windowSpaceLookup: [Int: Int] = [:]
        for group in sortedGroups {
            for entry in group.entries {
                windowSpaceLookup[entry.windowID] = group.spaceID
            }
        }

        for entry in orderedEntries {
            guard let spaceID = windowSpaceLookup[entry.windowID] else { continue }
            if seenSpaces.insert(spaceID).inserted { spaceOrder.append(spaceID) }
            entriesBySpace[spaceID, default: []].append(entry)
        }
        return spaceOrder.compactMap { spaceID in
            guard let entries = entriesBySpace[spaceID], !entries.isEmpty,
                  let original = sortedGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: entries
            )
        }
    }
}
