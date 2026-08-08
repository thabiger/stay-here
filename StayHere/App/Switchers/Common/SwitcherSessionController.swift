import AppKit
import CoreGraphics
import Core
import Foundation

@MainActor
final class SwitcherSessionController<Session: SwitcherSession, Snapshot, Selection>
where Session.Selection == Selection {
    private var session: Session?
    private var currentUpdateInfo: UpdateInfo?
    private var onOpenUpdate: (() -> Void)?

    private lazy var eventSupport = SwitcherEventControllerSupport(handler: self)
    private weak var delegate: (any SwitcherSessionDelegate<Session, Snapshot, Selection>)?
    private let panelPresenter: any SwitcherPanelPresenting<Snapshot, Selection>

    init(
        delegate: any SwitcherSessionDelegate<Session, Snapshot, Selection>,
        panelPresenter: any SwitcherPanelPresenting<Snapshot, Selection>
    ) {
        self.delegate = delegate
        self.panelPresenter = panelPresenter
    }

    var hasActiveSession: Bool { session != nil }

    /// The active session, if any. Read by the production refresh path
    /// (WindowSwitcherController.applyFreshPerSpaceEntries) and by tests.
    var activeSession: Session? { session }

    func start() {}

    func stop() {
        panelPresenter.releasePanel()
        session = nil
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        currentUpdateInfo = updateInfo
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        onOpenUpdate = callback
    }

    func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handle(event: event)
    }

    func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handleKeyDown(event: event)
    }

    func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventSupport.handleFlagsChanged(event: event)
    }

    func cancelSession() {
        switcherCancelActiveSession()
    }

    func openSwitcher() {
        let shortcut = switcherConfiguredShortcut()
        _ = ensureSession(using: shortcut, trigger: .explicit)
        showPanel()
    }

    func moveSelectionForward() {
        moveSelection(offset: 1)
    }

    func moveSelectionBackward() {
        moveSelection(offset: -1)
    }

    func commitSwitcherSelection() {
        switcherCommitOrDismissActiveSession()
    }

    func commitSelection(at position: Int) {
        guard let delegate, let item = delegate.item(at: position, in: session) else { return }
        let committed = delegate.commit(selection: item, in: session)
        if !committed {
            panelPresenter.dismissPanel()
            session = nil
        }
    }

    func closeSwitcher() {
        switcherCancelActiveSession()
    }

    /// Swaps the active session and re-presents the panel from a freshly built
    /// snapshot. No-op when no session is active (e.g., a background refresh
    /// completed after the switcher closed).
    func replaceActiveSession(with session: Session) {
        guard self.session != nil else { return }
        self.session = session
        showPanel()
    }

    private func moveSelection(offset: Int) {
        let shortcut = switcherConfiguredShortcut()
        _ = ensureSession(using: shortcut, trigger: .explicit)
        if var session = session, let delegate {
            delegate.moveSelection(in: &session, offset: offset)
            self.session = session
        }
        showPanel()
    }

    private func ensureSession(using shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Bool {
        guard session == nil, let delegate else { return false }
        session = delegate.buildSession(shortcut: shortcut, trigger: trigger)
        return session != nil
    }

    private func showPanel() {
        guard let delegate else { return }

        let snapshotStart = CFAbsoluteTimeGetCurrent()
        let snapshot = delegate.buildSnapshot(for: session)
        #if DEBUG
        let snapshotElapsed = CFAbsoluteTimeGetCurrent() - snapshotStart
        if snapshotElapsed > 0.033 {
            NSLog("[Switcher] buildSnapshot took \(snapshotElapsed * 1000)ms")
        }
        #endif

        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        let actions = SwitcherPanelActions<Selection>(
            onSelect: { [weak self] selection in
                guard let self, let delegate = self.delegate else { return }
                let committed = delegate.commit(selection: selection, in: self.session)
                if !committed {
                    self.panelPresenter.dismissPanel()
                    self.session = nil
                }
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
            onOpenUpdate: onOpenUpdate
        )

        #if DEBUG
        let presentStart = CFAbsoluteTimeGetCurrent()
        defer {
            let presentElapsed = CFAbsoluteTimeGetCurrent() - presentStart
            if presentElapsed > 0.033 {
                NSLog("[Switcher] presentSnapshot took \(presentElapsed * 1000)ms")
            }
        }
        #endif
        panelPresenter.presentSnapshot(snapshot, actions: actions, updateInfo: updateInfo)
    }
}

extension SwitcherSessionController: SwitcherEventSessionHandling {
    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut {
        session?.shortcut ?? delegate?.provideShortcut() ?? SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand])
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
        if !openedSession || (delegate?.movesSelectionOnNewSession ?? false) {
            if var session = session, let delegate {
                delegate.moveSelection(in: &session, offset: backward ? -1 : 1)
                self.session = session
            }
        }
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if (delegate?.shouldCommit(activeSession) ?? false), let selectedItem = activeSession.selectedItem {
            let committed = delegate?.commit(selection: selectedItem, in: activeSession) ?? false
            if !committed {
                panelPresenter.dismissPanel()
                session = nil
            }
        } else {
            panelPresenter.dismissPanel()
            session = nil
        }
    }

    func switcherCancelActiveSession() {
        delegate?.sessionDidEnd()
        panelPresenter.dismissPanel()
        session = nil
    }
}
