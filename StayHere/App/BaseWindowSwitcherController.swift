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
    let recencyTracker: WindowRecencyTracker
    let listBuilder: WindowListBuilder
    let panelPresenter: WindowSwitcherPanelPresenter

    var session: (any WindowSwitcherSessionProtocol)?
    var currentUpdateInfo: UpdateInfo?
    var onOpenUpdate: (() -> Void)?

    private let eventTapUnavailableLog: String

    private lazy var eventSupport = SwitcherEventControllerSupport(
        handler: self,
        eventTapUnavailableLog: eventTapUnavailableLog
    )

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelPresenter.panelPair }
        set { panelPresenter.panelPair = newValue }
    }

    internal var testSessionEntries: [WindowEntry]? {
        (session as? WindowSwitcherSession)?.flatEntries
    }

    internal var testSessionSpaceID: Int? {
        (session as? WindowSwitcherSession)?.spaceGroups.first?.spaceID
    }

    internal var testSessionSpaceGroups: [WindowListProvider.SpaceWindowGroup]? {
        (session as? WindowSwitcherSession)?.spaceGroups
    }

    internal var testSessionSelectedWindowID: Int? {
        session?.selectedWindowID
    }

    internal var testRecentWindowIDs: [Int] {
        recencyTracker.recentWindowIDs
    }

    init(
        settings: SettingsRepository,
        registry: SpaceRegistry,
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        mode: WindowSwitcherMode,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil,
        listProvider: WindowListProvider? = nil,
        focusService: WindowFocusService = WindowFocusService(),
        recencyTracker: WindowRecencyTracker? = nil,
        listBuilder: WindowListBuilder? = nil,
        panelPresenter: WindowSwitcherPanelPresenter? = nil
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

        self.recencyTracker = recencyTracker ?? WindowRecencyTracker()
        self.listBuilder = listBuilder ?? WindowListBuilder(
            mode: mode,
            listProvider: self.listProvider,
            recencyTracker: self.recencyTracker,
            registry: registry,
            settings: settings
        )
        self.panelPresenter = panelPresenter ?? WindowSwitcherPanelPresenter()

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

        guard let source = listBuilder.makeSessionSource() else { return false }

        session = WindowSwitcherSession(
            startingWindowID: source.startingWindowID,
            selectedWindowID: source.flatEntries.first?.windowID,
            shortcut: shortcut,
            spaceGroups: source.spaceGroups,
            flatEntries: source.flatEntries,
            trigger: trigger
        )
        return true
    }

    // MARK: - Panel management

    private func showPanel() {
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        let snapshot = listBuilder.buildSnapshot(for: session)
        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelPresenter.present(
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
        panelPresenter.dismiss()
    }

    internal func releasePanel() {
        panelPresenter.release()
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
        recencyTracker.recordSelection(entry.windowID, in: activeSession)
        commitSelectedEntry(entry)
    }

    private func commitSelectedEntry(_ entry: WindowEntry) {
        let windowSpaceIDs = cgsBridge.spacesForWindow(windowID: entry.windowID)
        let currentSpaceID = listProvider.currentContext()?.spaceID
        let targetSpaceID = windowSpaceIDs.first(where: { $0 != currentSpaceID })
            ?? windowSpaceIDs.first

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelPresenter.dismiss()
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
}
