import AppKit
import CoreGraphics
import Core
import SwiftUI

@MainActor
final class WindowSwitcherController {
    let mode: WindowSwitcherMode
    let settings: WindowSwitcherSettings & AllSpacesWindowSwitcherSettings
    let registry: any SpaceRegistryProtocol
    let shortcutProvider: () -> SpaceSwitcherShortcut
    let recencyTracker: WindowRecencyTracker
    let listBuilder: WindowListBuilder
    let panelPresenter: WindowSwitcherPanelPresenter
    private let windowSwitchUseCase: WindowSwitchUseCase
    private let listProvider: WindowListProvider

    private lazy var coordinator: SwitcherSessionController<WindowSwitcherSession, WindowSwitcherSnapshot, Int> = SwitcherSessionController(
        delegate: self,
        panelPresenter: panelPresenter
    )

    private var pendingCacheRefresh: DispatchWorkItem?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelPresenter.panelPair }
        set { panelPresenter.panelPair = newValue }
    }

    internal var testSessionEntries: [WindowEntry]? {
        coordinator.testSession?.flatEntries
    }

    internal var testSessionSpaceID: Int? {
        coordinator.testSession?.spaceGroups.first?.spaceID
    }

    internal var testSessionSpaceGroups: [SpaceWindowGroup]? {
        coordinator.testSession?.spaceGroups
    }

    internal var testSessionSelectedWindowID: Int? {
        coordinator.testSession?.selectedWindowID
    }

    internal var testRecentWindowIDs: [Int] {
        recencyTracker.recentWindowIDs
    }

    init(
        settings: WindowSwitcherSettings & AllSpacesWindowSwitcherSettings,
        registry: any SpaceRegistryProtocol,
        mode: WindowSwitcherMode,
        windowSwitchUseCase: WindowSwitchUseCase,
        cgsBridge: any CGSBridgeProtocol,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil,
        listProvider: WindowListProvider? = nil,
        recencyTracker: WindowRecencyTracker? = nil,
        listBuilder: WindowListBuilder? = nil,
        panelPresenter: WindowSwitcherPanelPresenter? = nil
    ) {
        self.mode = mode
        self.settings = settings
        self.registry = registry

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
        self.recencyTracker = recencyTracker ?? WindowRecencyTracker()
        self.listBuilder = listBuilder ?? WindowListBuilder(
            mode: mode,
            listProvider: self.listProvider,
            recencyTracker: self.recencyTracker,
            registry: registry,
            settings: settings
        )
        self.panelPresenter = panelPresenter ?? WindowSwitcherPanelPresenter()

        self.windowSwitchUseCase = windowSwitchUseCase

    }


    deinit {
        pendingCacheRefresh?.cancel()
        DispatchQueue.main.async { [listProvider] in
            listProvider.cancelAllSpacesRefresh()
        }
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
    }

    var hasActiveSession: Bool { coordinator.hasActiveSession }

    func start() {
        coordinator.start()
        guard mode == .allSpaces else { return }
        // Warm the all-spaces cache off the main thread so the first menu open
        // is instant. The background thread prevents UI blocking, so fire
        // immediately rather than waiting.
        listProvider.refreshAllSpacesCacheInBackground()
        // Refresh the cache when apps launch or terminate — the most common
        // window-set changes. Intra-app window open/close is not observable
        // via public APIs; the sessionDidEnd rebuild catches those.
        let center = NSWorkspace.shared.notificationCenter
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCacheRefresh() }
        }
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCacheRefresh() }
        }
    }

    func stop() {
        pendingCacheRefresh?.cancel()
        pendingCacheRefresh = nil
        listProvider.cancelAllSpacesRefresh()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver); self.launchObserver = nil }
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver); self.terminateObserver = nil }
        coordinator.stop()
    }

    /// Debounced cache refresh: waiting 2s after the last notification batches
    /// rapid sequences (e.g. launching a suite of apps at login) into a single
    /// rebuild.
    private func scheduleCacheRefresh() {
        pendingCacheRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            listProvider.refreshAllSpacesCacheInBackground()
        }
        pendingCacheRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    internal func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handle(event: event)
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handleKeyDown(event: event)
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handleFlagsChanged(event: event)
    }

    /// Invalidate the window-list cache.
    ///
    /// The current-space controller clears its cache on every session lifecycle
    /// event (open/commit/cancel/close) so the next interaction reflects an
    /// up-to-date per-space listing, which can change as windows switch spaces
    /// or as the user focuses different apps.
    ///
    /// The all-spaces controller also invalidates at session end, but then
    /// immediately rebuilds the cache in the background so the next menu open
    /// is fast while still picking up newly created/closed windows.
    private func invalidateListCache() {
        guard mode == .currentSpace else { return }
        listProvider.invalidateCache()
    }

    internal func cancelSession() {
        invalidateListCache()
        coordinator.cancelSession()
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        coordinator.setAvailableUpdate(updateInfo)
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        coordinator.setOnOpenUpdate(callback)
    }

    func openSwitcher() {
        coordinator.openSwitcher()
    }

    func moveSelectionForward() {
        coordinator.moveSelectionForward()
    }

    func moveSelectionBackward() {
        coordinator.moveSelectionBackward()
    }

    func commitSwitcherSelection() {
        invalidateListCache()
        coordinator.commitSwitcherSelection()
    }

    internal func switcherCommitOrDismissActiveSession() {
        coordinator.commitSwitcherSelection()
    }

    func commitSelection(at position: Int) {
        invalidateListCache()
        coordinator.commitSelection(at: position)
    }

    func closeSwitcher() {
        invalidateListCache()
        coordinator.closeSwitcher()
    }

    private func commitSelectedEntry(_ entry: WindowEntry) {
        invalidateListCache()
        let previousSpaceID = listProvider.currentContext()?.spaceID
        panelPresenter.dismiss()
        coordinator.closeSwitcher()

        Task { @MainActor [weak self] in
            await self?.windowSwitchUseCase.execute(entry: entry, previousSpaceID: previousSpaceID)
        }
    }
}

@MainActor
extension WindowSwitcherController: @preconcurrency SwitcherSessionDelegate {
    var movesSelectionOnNewSession: Bool { false }

    func provideShortcut() -> SpaceSwitcherShortcut {
        shortcutProvider()
    }

    func buildSession(shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> WindowSwitcherSession? {
        guard let source = listBuilder.makeSessionSource() else { return nil }
        return WindowSwitcherSession(
            startingWindowID: source.startingWindowID,
            selectedWindowID: source.flatEntries.first?.windowID,
            shortcut: shortcut,
            spaceGroups: source.spaceGroups,
            flatEntries: source.flatEntries,
            trigger: trigger
        )
    }

    func moveSelection(in session: inout WindowSwitcherSession, offset: Int) {
        let entries = session.flatEntries
        guard !entries.isEmpty else { return }
        let ids = entries.map(\.windowID)
        let currentSelection = session.selectedWindowID ?? session.startingWindowID ?? ids.first
        let nextSelection = offset > 0
            ? WindowSwitcherSelection.nextWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
            : WindowSwitcherSelection.previousWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
        session.selectedWindowID = nextSelection
    }

    func buildSnapshot(for session: WindowSwitcherSession?) -> WindowSwitcherSnapshot {
        listBuilder.buildSnapshot(for: session)
    }

    func item(at position: Int, in session: WindowSwitcherSession?) -> Int? {
        guard let session, position > 0, position <= session.flatEntries.count else { return nil }
        return session.flatEntries[position - 1].windowID
    }

    func shouldCommit(_ session: WindowSwitcherSession) -> Bool {
        true
    }

    func commit(selection windowID: Int, in session: WindowSwitcherSession?) -> Bool {
        guard let session,
              let entry = session.flatEntries.first(where: { $0.windowID == windowID }) else {
            return false
        }
        recencyTracker.recordSelection(windowID, in: session)
        commitSelectedEntry(entry)
        return true
    }

    func sessionDidEnd() {
        // For the current-space controller: cache is cold until the next open,
        // which is fast anyway (single-space enumeration).
        if mode == .currentSpace {
            listProvider.invalidateCache()
            return
        }
        // For the all-spaces controller: refresh the cache off-main. The
        // last-good snapshot keeps serving reads while the rebuild runs, so
        // a quick second invocation never blocks behind the AX/CGS work.
        listProvider.refreshAllSpacesCacheInBackground()
    }
}
