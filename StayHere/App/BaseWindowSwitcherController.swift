import AppKit
import CoreGraphics
import Core
import SwiftUI

final class WindowSwitcherController: SwitcherEventSessionHandling {
    let mode: WindowSwitcherMode
    let settings: SettingsRepository
    let registry: SpaceRegistry
    let cgsBridge: any CGSBridgeProtocol
    let listProvider: WindowListProvider
    let focusService: WindowFocusService
    let shortcutProvider: () -> SpaceSwitcherShortcut

    private struct Session: WindowSwitcherSessionProtocol {
        let startingWindowID: Int?
        var selectedWindowID: Int?
        let shortcut: SpaceSwitcherShortcut
        let spaceGroups: [WindowListProvider.SpaceWindowGroup]
        let flatEntries: [WindowEntry]
        let trigger: SwitcherSessionTrigger
    }

    private let panelManager = WindowSwitcherPanelManager()

    var session: (any WindowSwitcherSessionProtocol)?
    var recentWindowIDs: [Int] = []
    var currentUpdateInfo: UpdateInfo?
    var onOpenUpdate: (() -> Void)?

    private let eventTapUnavailableLog: String

    private lazy var eventSupport = SwitcherEventControllerSupport(
        handler: self,
        eventTapUnavailableLog: eventTapUnavailableLog
    )

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var testSessionEntries: [WindowEntry]? {
        (session as? Session)?.flatEntries
    }

    internal var testSessionSpaceID: Int? {
        (session as? Session)?.spaceGroups.first?.spaceID
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
        mode: WindowSwitcherMode,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil,
        listProvider: WindowListProvider? = nil,
        focusService: WindowFocusService = WindowFocusService()
    ) {
        self.mode = mode
        self.settings = settings
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.focusService = focusService

        let resolvedShortcut = shortcutProvider ?? {
            switch mode {
            case .currentSpace:
                return SpaceSwitcherShortcut.parse(settings.windowSwitcherShortcutText)
                    ?? SpaceSwitcherShortcut.parse("command+`")
                    ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
            case .allSpaces:
                return SpaceSwitcherShortcut.parse(settings.allSpacesWindowSwitcherShortcutText)
                    ?? SpaceSwitcherShortcut.parse("command+shift+`")
                    ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift])
            }
        }
        self.shortcutProvider = resolvedShortcut

        self.listProvider = listProvider ?? WindowListProvider(
            registry: registry,
            cgsBridge: cgsBridge,
            settings: settings
        )

        switch mode {
        case .currentSpace:
            self.eventTapUnavailableLog = "window-switcher failed=event-tap-unavailable"
        case .allSpaces:
            self.eventTapUnavailableLog = "all-spaces-window-switcher failed=event-tap-unavailable"
        }
    }

    var hasActiveSession: Bool { session != nil }

    deinit {
        stop()
    }

    func start() {
        eventSupport.start()
    }

    func stop() {
        releasePanel()
        session = nil
        eventSupport.stop()
    }

    internal func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handle(event: event)
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handleKeyDown(event: event)
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handleFlagsChanged(event: event)
    }

    internal func cancelSession() {
        DispatchQueue.main.async { [weak self] in
            self?.switcherCancelActiveSession()
        }
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        currentUpdateInfo = updateInfo
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        onOpenUpdate = callback
    }

    // MARK: - Session creation

    @discardableResult
    internal func ensureSession(using shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Bool {
        guard session == nil else { return false }

        let spaceGroups: [WindowListProvider.SpaceWindowGroup]
        switch mode {
        case .currentSpace:
            guard let context = listProvider.currentContext() else { return false }
            let entries = listProvider.entries(in: context)
            let label = registry.name(for: context.spaceID)
            spaceGroups = [WindowListProvider.SpaceWindowGroup(
                spaceID: context.spaceID,
                spaceLabel: label,
                entries: entries
            )]
        case .allSpaces:
            let groups = listProvider.entriesForAllSpaces()
            guard !groups.isEmpty else { return false }
            spaceGroups = groups
        }

        let sortedGroups = recentEntries(from: spaceGroups)
        let flatSorted = sortedGroups.flatMap(\.entries)

        let startingWindowID = flatSorted.first?.windowID
        let orderedEntries = WindowSwitcherSelection.sessionOrder(fromRecentEntries: flatSorted)

        let orderedGroups: [WindowListProvider.SpaceWindowGroup]
        if mode == .currentSpace, sortedGroups.isEmpty, spaceGroups.count == 1 {
            orderedGroups = spaceGroups
        } else {
            orderedGroups = Self.spaceGroups(from: orderedEntries, using: sortedGroups)
        }

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

    // MARK: - Panel management

    private func showPanel() {
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        let snapshot = buildSnapshot()
        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.present(
                snapshot: snapshot,
                onSelect: { [weak self] entry in
                    self?.commitSelection(entry)
                },
                onFocusLost: { [weak self] in
                    self?.switcherCancelActiveSession()
                },
                onCommit: enablePanelKeyboardHandling ? { [weak self] in
                    self?.commitSwitcherSelection()
                } : nil,
                onCancel: enablePanelKeyboardHandling ? { [weak self] in
                    self?.closeSwitcher()
                } : nil,
                onMoveUp: enablePanelKeyboardHandling ? { [weak self] in
                    self?.moveSelectionBackward()
                } : nil,
                onMoveDown: enablePanelKeyboardHandling ? { [weak self] in
                    self?.moveSelectionForward()
                } : nil,
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        }
    }

    internal func dismissPanel() {
        panelManager.dismiss()
    }

    internal func releasePanel() {
        panelManager.release()
    }

    // MARK: - Selection

    private func moveSelection(offset: Int) {
        guard var session else { return }
        let entries = session.flatEntries
        guard !entries.isEmpty else { return }
        let ids = entries.map(\.windowID)
        let currentSelection = session.selectedWindowID ?? session.startingWindowID ?? ids.first
        let nextSelection = offset > 0
            ? WindowSwitcherSelection.nextWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
            : WindowSwitcherSelection.previousWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
        session.selectedWindowID = nextSelection
        self.session = session
    }

    private func commitSelection(_ entry: WindowEntry) {
        let activeSession = session
        WindowSwitcherSelection.recordSelection(
            entry.windowID,
            in: activeSession,
            recentWindowIDs: &recentWindowIDs
        )
        commitSelectedEntry(entry)
    }

    private func commitSelectedEntry(_ entry: WindowEntry) {
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

    // MARK: - Public API

    func openSwitcher() {
        let shortcut = switcherConfiguredShortcut()
        ensureSession(using: shortcut, trigger: .explicit)
        showPanel()
    }

    func moveSelectionForward() {
        let shortcut = switcherConfiguredShortcut()
        ensureSession(using: shortcut, trigger: .explicit)
        moveSelection(offset: 1)
        showPanel()
    }

    func moveSelectionBackward() {
        let shortcut = switcherConfiguredShortcut()
        ensureSession(using: shortcut, trigger: .explicit)
        moveSelection(offset: -1)
        showPanel()
    }

    func commitSwitcherSelection() {
        switcherCommitOrDismissActiveSession()
    }

    func commitSelection(at position: Int) {
        guard let session else { return }
        guard position > 0, position <= session.flatEntries.count else { return }
        commitSelection(session.flatEntries[position - 1])
    }

    func closeSwitcher() {
        switcherCancelActiveSession()
    }

    internal func displayTitle(for entry: WindowEntry) -> String {
        WindowSwitcherTitleFormat.displayTitle(
            appName: entry.appName,
            windowTitle: entry.windowTitle,
            format: settings.windowSwitcherTitleFormat
        )
    }

    // MARK: - SwitcherEventSessionHandling

    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut {
        session?.shortcut ?? shortcutProvider()
    }

    func switcherHasActiveSession() -> Bool {
        session != nil
    }

    func switcherSessionModifiers() -> CGEventFlags? {
        guard session?.trigger == .keyboard else { return nil }
        return session?.shortcut.modifiers
    }

    func switcherEnsureSessionAndMoveSelection(backward: Bool) {
        let shortcut = switcherConfiguredShortcut()
        let openedSession = ensureSession(using: shortcut, trigger: .keyboard)
        if !openedSession {
            moveSelection(offset: backward ? -1 : 1)
        }
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if let selectedID = activeSession.selectedWindowID,
           let entry = activeSession.flatEntries.first(where: { $0.windowID == selectedID }) {
            commitSelection(entry)
        } else {
            dismissPanel()
            session = nil
        }
    }

    func switcherCancelActiveSession() {
        dismissPanel()
        session = nil
    }

    // MARK: - Snapshot building

    private func buildSnapshot() -> WindowSwitcherSnapshot {
        let spaceGroups: [WindowListProvider.SpaceWindowGroup]
        let selectedID: Int?
        if let session {
            spaceGroups = (session as! Session).spaceGroups
            selectedID = session.selectedWindowID ?? session.flatEntries.first?.windowID
        } else {
            let groups: [WindowListProvider.SpaceWindowGroup]
            switch mode {
            case .currentSpace:
                guard let context = listProvider.currentContext() else {
                    return emptySnapshot()
                }
                let entries = listProvider.entries(in: context)
                let label = registry.name(for: context.spaceID)
                groups = [WindowListProvider.SpaceWindowGroup(
                    spaceID: context.spaceID,
                    spaceLabel: label,
                    entries: entries
                )]
            case .allSpaces:
                groups = listProvider.entriesForAllSpaces()
            }
            let sortedGroups = recentEntries(from: groups)
            let flatSorted = sortedGroups.flatMap(\.entries)
            let ordered = WindowSwitcherSelection.sessionOrder(fromRecentEntries: flatSorted)
            if mode == .currentSpace, sortedGroups.isEmpty, groups.count == 1 {
                spaceGroups = groups
            } else {
                spaceGroups = Self.spaceGroups(from: ordered, using: sortedGroups)
            }
            selectedID = ordered.first?.windowID
        }

        let viewGroups: [WindowSwitcherSpaceGroup] = spaceGroups.map { group in
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

    // MARK: - Recency

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

    // MARK: - Panel height

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
}
