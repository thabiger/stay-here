import AppKit
import CoreGraphics
import Core
import SwiftUI

final class WindowSwitcherController: BaseWindowSwitcherController {
    private struct Session: WindowSwitcherSessionProtocol {
        let startingWindowID: Int?
        var selectedWindowID: Int?
        let shortcut: SpaceSwitcherShortcut
        let entries: [WindowEntry]
        let spaceContext: WindowSpaceContext
        let trigger: SwitcherSessionTrigger

        var flatEntries: [WindowEntry] { entries }
    }

    private let panelManager = WindowSwitcherPanelManager()

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var testSessionEntries: [WindowEntry]? {
        (session as? Session)?.entries
    }

    internal var testSessionSpaceID: Int? {
        (session as? Session)?.spaceContext.spaceID
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
            SpaceSwitcherShortcut.parse(settings.windowSwitcherShortcutText)
                ?? SpaceSwitcherShortcut.parse("command+`")
                ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
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
            eventTapUnavailableLog: "window-switcher failed=event-tap-unavailable"
        )
    }

    override internal func ensureSessionImpl(
        using shortcut: SpaceSwitcherShortcut,
        trigger: SwitcherSessionTrigger
    ) -> Bool {
        guard let context = listProvider.currentContext() else { return false }

        let recentEntries = recentEntries(in: context)
        let orderedEntries = WindowSwitcherSelection.sessionOrder(fromRecentEntries: recentEntries)
        session = Session(
            startingWindowID: recentEntries.first?.windowID,
            selectedWindowID: orderedEntries.first?.windowID,
            shortcut: shortcut,
            entries: orderedEntries,
            spaceContext: context,
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.dismiss()
            self.session = nil
            self.focusService.focusWindow(entry: entry)
        }
    }

    override internal func dismissPanel() {
        panelManager.dismiss()
    }

    override internal func releasePanel() {
        panelManager.release()
    }

    static func panelHeight(itemCount: Int, screenHeight: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 40
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let emptyBodyHeight: CGFloat = 56
        let bodyHeight = itemCount == 0
            ? emptyBodyHeight
            : CGFloat(itemCount) * rowHeight + listPadding
        let minimumHeight = headerHeight + min(emptyBodyHeight, rowHeight + listPadding)
        let maxHeight = max(screenHeight - 80, minimumHeight)
        return min(headerHeight + bodyHeight, maxHeight)
    }

    private func recentEntries(in context: WindowSpaceContext) -> [WindowEntry] {
        let entries = listProvider.entries(in: context)
        guard !entries.isEmpty else {
            recentWindowIDs = []
            return []
        }

        let entryIDs = Set(entries.map(\.windowID))
        let orderedIDs = recentWindowIDs.filter { entryIDs.contains($0) }

        let knownIDs = Set(orderedIDs)
        let unknownEntries = entries.filter { !knownIDs.contains($0.windowID) }
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.windowID, $0) })
        let orderedEntries = orderedIDs.compactMap { entriesByID[$0] } + unknownEntries
        recentWindowIDs = orderedEntries.map(\.windowID)
        return orderedEntries
    }

    private func buildSnapshot() -> WindowSwitcherSnapshot {
        let entries: [WindowEntry]
        let selectedID: Int?
        if let session {
            entries = session.flatEntries
            selectedID = session.selectedWindowID ?? entries.first?.windowID
        } else {
            guard let context = listProvider.currentContext() else {
                return WindowSwitcherSnapshot(
                    items: [],
                    title: "Window Switcher",
                    emptyMessage: "No windows on this Space"
                )
            }
            entries = WindowSwitcherSelection.sessionOrder(fromRecentEntries: recentEntries(in: context))
            selectedID = entries.first?.windowID
        }
        let items = entries.map { entry in
            WindowSwitcherItem(
                id: entry.windowID,
                icon: entry.icon,
                title: displayTitle(for: entry),
                entry: entry,
                isSelected: entry.windowID == selectedID
            )
        }
        return WindowSwitcherSnapshot(
            items: items,
            title: "Window Switcher",
            emptyMessage: "No windows on this Space"
        )
    }
}

