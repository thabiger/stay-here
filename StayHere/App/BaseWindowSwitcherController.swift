import AppKit
import CoreGraphics
import Core
import SwiftUI

class BaseWindowSwitcherController: SwitcherEventSessionHandling {
    let settings: SettingsRepository
    let registry: SpaceRegistry
    let cgsBridge: any CGSBridgeProtocol
    let listProvider: WindowListProvider
    let focusService: WindowFocusService
    let shortcutProvider: () -> SpaceSwitcherShortcut

    var session: (any WindowSwitcherSessionProtocol)?
    var recentWindowIDs: [Int] = []
    var currentUpdateInfo: UpdateInfo?
    var onOpenUpdate: (() -> Void)?

    private let eventTapUnavailableLog: String

    private lazy var eventSupport = SwitcherEventControllerSupport(
        handler: self,
        eventTapUnavailableLog: eventTapUnavailableLog
    )

    init(
        settings: SettingsRepository,
        registry: SpaceRegistry,
        cgsBridge: any CGSBridgeProtocol,
        shortcutProvider: @escaping () -> SpaceSwitcherShortcut,
        listProvider: WindowListProvider,
        focusService: WindowFocusService,
        eventTapUnavailableLog: String
    ) {
        self.settings = settings
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.shortcutProvider = shortcutProvider
        self.listProvider = listProvider
        self.focusService = focusService
        self.eventTapUnavailableLog = eventTapUnavailableLog
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

    // MARK: - Subclass hooks

    internal func ensureSessionImpl(
        using shortcut: SpaceSwitcherShortcut,
        trigger: SwitcherSessionTrigger
    ) -> Bool { false }

    internal func presentPanel(
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)?,
        onCommit: (() -> Void)?,
        onCancel: (() -> Void)?,
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?
    ) {}

    internal func commitSelectedEntry(_ entry: WindowEntry) {}

    internal func dismissPanel() {}

    internal func releasePanel() {}

    // MARK: - Shared session logic

    @discardableResult
    internal func ensureSession(using shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Bool {
        guard session == nil else { return false }
        return ensureSessionImpl(using: shortcut, trigger: trigger)
    }

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

    private func showPanel() {
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        presentPanel(
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
            } : nil
        )
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
}
