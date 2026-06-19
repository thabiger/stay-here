import AppKit
import CoreGraphics
import Core
import SwiftUI

final class AllSpacesWindowSwitcherController: BaseWindowSwitcherController {
    private struct Session: WindowSwitcherSessionProtocol {
        let startingWindowID: Int?
        var selectedWindowID: Int?
        let shortcut: SpaceSwitcherShortcut
        let spaceGroups: [WindowListProvider.SpaceWindowGroup]
        let flatEntries: [WindowEntry]
        let trigger: SwitcherSessionTrigger
    }

    private let panelManager = AllSpacesWindowSwitcherPanelManager()

    var panelPair: (window: NSPanel, hosting: NSHostingController<AllSpacesWindowSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var testSessionSpaceGroups: [WindowListProvider.SpaceWindowGroup]? {
        (session as? Session)?.spaceGroups
    }

    internal var testSessionSelectedWindowID: Int? {
        session?.selectedWindowID
    }

    internal var testRecentWindowIDs: [Int] {
        recentWindowIDs
    }

    init(
        settings: SettingsRepository,
        registry: SpaceRegistry,
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil,
        listProvider: WindowListProvider? = nil,
        focusService: WindowFocusService = WindowFocusService()
    ) {
        let resolvedShortcut = shortcutProvider ?? {
            SpaceSwitcherShortcut.parse(settings.allSpacesWindowSwitcherShortcutText)
                ?? SpaceSwitcherShortcut.parse("command+shift+`")
                ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift])
        }
        let resolvedList = listProvider ?? WindowListProvider(
            registry: registry,
            cgsBridge: cgsBridge,
            settings: settings
        )
        super.init(
            settings: settings,
            registry: registry,
            cgsBridge: cgsBridge,
            shortcutProvider: resolvedShortcut,
            listProvider: resolvedList,
            focusService: focusService,
            eventTapUnavailableLog: "all-spaces-window-switcher failed=event-tap-unavailable"
        )
    }

    override internal func ensureSessionImpl(
        using shortcut: SpaceSwitcherShortcut,
        trigger: SwitcherSessionTrigger
    ) -> Bool {
        let spaceGroups = listProvider.entriesForAllSpaces()
        let flatEntries = spaceGroups.flatMap(\.entries)
        guard !flatEntries.isEmpty else { return false }

        let sortedGroups = recentEntries(from: spaceGroups)
        let flatSorted = sortedGroups.flatMap(\.entries)

        let startingWindowID = flatSorted.first?.windowID
        let orderedEntries = WindowSwitcherSelection.sessionOrder(fromRecentEntries: flatSorted)
        let orderedGroups = Self.spaceGroups(from: orderedEntries, using: sortedGroups)

        session = Session(
            startingWindowID: startingWindowID,
            selectedWindowID: orderedEntries.first?.windowID,
            shortcut: shortcut,
            spaceGroups: orderedGroups,
            flatEntries: orderedEntries,
            trigger: trigger
        )
        return true
    }

    override internal func presentPanel(
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)?,
        onCommit: (() -> Void)?,
        onCancel: (() -> Void)?,
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?
    ) {
        let snapshot = buildSnapshot()
        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.present(
                snapshot: snapshot,
                onSelect: onSelect,
                onFocusLost: onFocusLost,
                onCommit: onCommit,
                onCancel: onCancel,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        }
    }

    override internal func commitSelectedEntry(_ entry: WindowEntry) {
        // Determine which space the selected window belongs to so we can
        // switch to it before focusing.  Without an explicit space switch,
        // Accessibility-based focus does not move between spaces.
        let windowSpaceIDs = cgsBridge.spacesForWindow(windowID: entry.windowID)
        let currentSpaceID = listProvider.currentContext()?.spaceID
        let targetSpaceID = windowSpaceIDs.first(where: { $0 != currentSpaceID })
            ?? windowSpaceIDs.first

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.dismiss()
            self.session = nil

            if let targetSpaceID, targetSpaceID != currentSpaceID {
                _ = self.registry.switchToSpace(targetSpaceID)
            }

            self.focusService.focusWindow(entry: entry)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                let currentContext = self.listProvider.currentContext()
                if currentContext?.spaceID != currentSpaceID {
                    self.registry.refreshSpaces()
                }
            }
        }
    }

    override internal func dismissPanel() {
        panelManager.dismiss()
    }

    override internal func releasePanel() {
        panelManager.release()
    }

    static func panelHeight(spaceGroupCount: Int, totalWindowCount: Int, screenHeight: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 40
        let sectionHeaderHeight: CGFloat = 28
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let emptyBodyHeight: CGFloat = 56
        let bodyHeight = totalWindowCount == 0
            ? emptyBodyHeight
            : CGFloat(spaceGroupCount) * sectionHeaderHeight
              + CGFloat(totalWindowCount) * rowHeight
              + listPadding
        let minimumHeight = headerHeight + min(emptyBodyHeight, rowHeight + listPadding)
        let maxHeight = max(screenHeight - 80, minimumHeight)
        return min(headerHeight + bodyHeight, maxHeight)
    }

    private static func spaceGroups(
        from orderedEntries: [WindowEntry],
        using sortedGroups: [WindowListProvider.SpaceWindowGroup]
    ) -> [WindowListProvider.SpaceWindowGroup] {
        var entriesBySpace: [Int: [WindowEntry]] = [:]
        var spaceOrder: [Int] = []
        for entry in orderedEntries {
            guard let spaceID = sortedGroups.first(where: { group in
                group.entries.contains(where: { $0.windowID == entry.windowID })
            })?.spaceID else { continue }
            if !spaceOrder.contains(spaceID) { spaceOrder.append(spaceID) }
            entriesBySpace[spaceID, default: []].append(entry)
        }
        return spaceOrder.compactMap { spaceID in
            guard let entries = entriesBySpace[spaceID], !entries.isEmpty,
                  let original = sortedGroups.first(where: { $0.spaceID == spaceID })
            else { return nil }
            return WindowListProvider.SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: original.spaceLabel,
                entries: entries
            )
        }
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

    private func buildSnapshot() -> AllSpacesWindowSwitcherSnapshot {
        let spaceGroups: [WindowListProvider.SpaceWindowGroup]
        let selectedID: Int?
        if let session {
            spaceGroups = (session as! Session).spaceGroups
            selectedID = session.selectedWindowID ?? session.flatEntries.first?.windowID
        } else {
            let groups = listProvider.entriesForAllSpaces()
            let sortedGroups = recentEntries(from: groups)
            let flatSorted = sortedGroups.flatMap(\.entries)
            let ordered = WindowSwitcherSelection.sessionOrder(fromRecentEntries: flatSorted)
            spaceGroups = Self.spaceGroups(from: ordered, using: sortedGroups)
            selectedID = ordered.first?.windowID
        }

        let viewGroups: [AllSpacesWindowSwitcherSpaceGroup] = spaceGroups.map { group in
            let items = group.entries.map { entry in
                AllSpacesWindowSwitcherItem(
                    id: entry.windowID,
                    icon: entry.icon,
                    title: displayTitle(for: entry),
                    entry: entry,
                    isSelected: entry.windowID == selectedID
                )
            }
            return AllSpacesWindowSwitcherSpaceGroup(
                id: group.spaceID,
                spaceLabel: group.spaceLabel,
                items: items
            )
        }

        return AllSpacesWindowSwitcherSnapshot(
            spaceGroups: viewGroups,
            title: "All Spaces Window Switcher",
            emptyMessage: "No windows across any Space"
        )
    }
}

