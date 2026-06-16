import AppKit
import CoreGraphics
import Core
import SwiftUI

final class WindowSwitcherController: SwitcherEventSessionHandling {
    private struct Session {
        let startingWindowID: Int?
        var selectedWindowID: Int?
        let shortcut: SpaceSwitcherShortcut
        let entries: [WindowEntry]
        let spaceContext: WindowSpaceContext

        var didChangeSelection: Bool {
            selectedWindowID != nil && selectedWindowID != startingWindowID
        }
    }

    private let settings: SettingsRepository
    private let shortcutProvider: () -> SpaceSwitcherShortcut
    private let listProvider: WindowListProvider
    private let focusService: WindowFocusService
    private let panelManager = WindowSwitcherPanelManager()
    private lazy var eventSupport = SwitcherEventControllerSupport(
        handler: self,
        eventTapUnavailableLog: "window-switcher failed=event-tap-unavailable"
    )

    private var session: Session?
    private var recentWindowIDs: [Int] = []
    private var currentUpdateInfo: UpdateInfo?
    private var onOpenUpdate: (() -> Void)?

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var hasActiveSession: Bool { session != nil }

    internal var testSessionEntries: [WindowEntry]? {
        session?.entries
    }

    internal var testSessionSpaceID: Int? {
        session?.spaceContext.spaceID
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
        self.settings = settings
        self.shortcutProvider = shortcutProvider ?? {
            SpaceSwitcherShortcut.parse(settings.windowSwitcherShortcutText)
                ?? SpaceSwitcherShortcut.parse("command+`")
                ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
        }
        self.listProvider = listProvider ?? WindowListProvider(
            registry: registry,
            cgsBridge: cgsBridge,
            settings: settings
        )
        self.focusService = focusService
    }

    deinit {
        stop()
    }

    func start() {
        eventSupport.start()
    }

    func stop() {
        panelManager.release()
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

    @discardableResult
    private func ensureSession(using shortcut: SpaceSwitcherShortcut) -> Bool {
        guard session == nil else { return false }
        guard let context = listProvider.currentContext() else { return false }

        let recentEntries = recentEntries(in: context)
        let orderedEntries = Self.sessionOrder(fromRecentEntries: recentEntries)
        session = Session(
            startingWindowID: recentEntries.first?.windowID,
            selectedWindowID: orderedEntries.first?.windowID,
            shortcut: shortcut,
            entries: orderedEntries,
            spaceContext: context
        )
        return true
    }

    private static func sessionOrder(fromRecentEntries entries: [WindowEntry]) -> [WindowEntry] {
        guard entries.count > 1 else { return entries }
        return [entries[1], entries[0]] + Array(entries.dropFirst(2))
    }

    private func recentEntries(in context: WindowSpaceContext) -> [WindowEntry] {
        let entries = listProvider.entries(in: context)
        guard !entries.isEmpty else {
            recentWindowIDs = []
            return []
        }

        let entryIDs = Set(entries.map(\.windowID))
        var orderedIDs = recentWindowIDs.filter { entryIDs.contains($0) }
        if let focusedWindowID = listProvider.focusedWindowID(),
           entryIDs.contains(focusedWindowID) {
            orderedIDs.removeAll { $0 == focusedWindowID }
            orderedIDs.insert(focusedWindowID, at: 0)
        }

        let knownIDs = Set(orderedIDs)
        let unknownEntries = entries.filter { !knownIDs.contains($0.windowID) }
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.windowID, $0) })
        let orderedEntries = orderedIDs.compactMap { entriesByID[$0] } + unknownEntries
        recentWindowIDs = orderedEntries.map(\.windowID)
        return orderedEntries
    }

    private static func recentOrder(fromSessionEntries entries: [WindowEntry], startingWindowID: Int?) -> [Int] {
        let ids = entries.map(\.windowID)
        guard let startingWindowID, ids.contains(startingWindowID) else { return ids }
        return [startingWindowID] + ids.filter { $0 != startingWindowID }
    }

    private func recordSelection(_ selectedWindowID: Int, in activeSession: Session?) {
        guard let activeSession else {
            recentWindowIDs.removeAll { $0 == selectedWindowID }
            recentWindowIDs.insert(selectedWindowID, at: 0)
            return
        }

        let previousRecentIDs = Self.recentOrder(
            fromSessionEntries: activeSession.entries,
            startingWindowID: activeSession.startingWindowID
        )
        var orderedIDs = [selectedWindowID]
        if let startingWindowID = activeSession.startingWindowID,
           startingWindowID != selectedWindowID {
            orderedIDs.append(startingWindowID)
        }
        orderedIDs += previousRecentIDs.filter { id in
            id != selectedWindowID && id != activeSession.startingWindowID
        }
        recentWindowIDs = orderedIDs
    }

    private func moveSelection(offset: Int) {
        guard var session else { return }
        let entries = session.entries
        guard !entries.isEmpty else { return }
        let ids = entries.map(\.windowID)
        let currentSelection = session.selectedWindowID ?? session.startingWindowID ?? ids.first
        let nextSelection = offset > 0
            ? nextWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
            : previousWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
        session.selectedWindowID = nextSelection
        self.session = session
    }

    private func nextWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.first
        }
        return orderedWindowIDs[(index + 1) % orderedWindowIDs.count]
    }

    private func previousWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.last
        }
        return orderedWindowIDs[(index - 1 + orderedWindowIDs.count) % orderedWindowIDs.count]
    }

    private func commitSelection(_ entry: WindowEntry) {
        let activeSession = session
        recordSelection(entry.windowID, in: activeSession)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.dismiss()
            self.session = nil
            self.focusService.focusWindow(entry: entry)
        }
    }

    private func showPanel() {
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
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        }
    }

    internal static func panelHeight(itemCount: Int, screenHeight: CGFloat) -> CGFloat {
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

    private func buildSnapshot() -> WindowSwitcherSnapshot {
        let entries: [WindowEntry]
        let selectedID: Int?
        if let session {
            entries = session.entries
            selectedID = session.selectedWindowID ?? entries.first?.windowID
        } else {
            guard let context = listProvider.currentContext() else {
                return WindowSwitcherSnapshot(
                    items: [],
                    title: "Window Switcher",
                    emptyMessage: "No windows on this Space"
                )
            }
            entries = Self.sessionOrder(fromRecentEntries: recentEntries(in: context))
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

    private func displayTitle(for entry: WindowEntry) -> String {
        WindowSwitcherTitleFormat.displayTitle(
            appName: entry.appName,
            windowTitle: entry.windowTitle,
            format: settings.windowSwitcherTitleFormat
        )
    }

    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut {
        session?.shortcut ?? shortcutProvider()
    }

    func switcherHasActiveSession() -> Bool {
        session != nil
    }

    func switcherSessionModifiers() -> CGEventFlags? {
        session?.shortcut.modifiers
    }

    func switcherEnsureSessionAndMoveSelection(backward: Bool) {
        let shortcut = switcherConfiguredShortcut()
        let openedSession = ensureSession(using: shortcut)
        if !openedSession {
            moveSelection(offset: backward ? -1 : 1)
        }
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if let selectedID = activeSession.selectedWindowID,
           let entry = activeSession.entries.first(where: { $0.windowID == selectedID }) {
            commitSelection(entry)
        } else {
            panelManager.dismiss()
            session = nil
        }
    }

    func switcherCancelActiveSession() {
        panelManager.dismiss()
        session = nil
    }
}
