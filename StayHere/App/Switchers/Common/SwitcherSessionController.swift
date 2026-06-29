import AppKit
import CoreGraphics
import Core
import Foundation

final class SwitcherSessionController<Session: SwitcherSession, Snapshot, Selection>
where Session.Selection == Selection {
    typealias BuildSession = (SpaceSwitcherShortcut, SwitcherSessionTrigger) -> Session?
    typealias MoveSelection = (inout Session, Int) -> Void
    typealias BuildSnapshot = (Session?) -> Snapshot
    typealias ItemAtPosition = (Session?, Int) -> Selection?
    typealias CommitSelection = (Session?, Selection) -> Bool
    typealias ShouldCommit = (Session) -> Bool
    typealias PresentSnapshot = (
        Snapshot,
        @escaping (Selection) -> Void,
        (() -> Void)?,
        (() -> Void)?,
        (() -> Void)?,
        (() -> Void)?,
        (() -> Void)?,
        UpdateInfo?,
        (() -> Void)?
    ) -> Void
    typealias DismissPanel = () -> Void
    typealias ReleasePanel = () -> Void

    private var session: Session?
    private var currentUpdateInfo: UpdateInfo?
    private var onOpenUpdate: (() -> Void)?

    private lazy var eventSupport = SwitcherEventControllerSupport(handler: self)
    private let configuration: SwitcherConfiguration<Session, Snapshot, Selection>

    init(configuration: SwitcherConfiguration<Session, Snapshot, Selection>) {
        self.configuration = configuration
    }

    var hasActiveSession: Bool { session != nil }

    var testSession: Session? { session }

    func start() {}

    func stop() {
        configuration.releasePanel()
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
        DispatchQueue.main.async { [weak self] in
            self?.switcherCancelActiveSession()
        }
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
        guard let item = configuration.itemAtPosition(session, position) else { return }
        let committed = configuration.commitSelection(session, item)
        if !committed {
            configuration.dismissPanel()
            session = nil
        }
    }

    func closeSwitcher() {
        switcherCancelActiveSession()
    }

    private func moveSelection(offset: Int) {
        let shortcut = switcherConfiguredShortcut()
        _ = ensureSession(using: shortcut, trigger: .explicit)
        if var session = session {
            configuration.moveSelection(&session, offset)
            self.session = session
        }
        showPanel()
    }

    private func ensureSession(using shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Bool {
        guard session == nil else { return false }
        session = configuration.buildSession(shortcut, trigger)
        return session != nil
    }

    private func showPanel() {
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        let snapshot = configuration.buildSnapshot(session)
        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        let actions = SwitcherPanelActions<Selection>(
            onSelect: { [weak self] selection in
                let committed = self?.configuration.commitSelection(self?.session, selection) ?? false
                if !committed {
                    self?.configuration.dismissPanel()
                    self?.session = nil
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
        configuration.presentSnapshot(snapshot, actions, updateInfo)
    }
}

extension SwitcherSessionController: SwitcherEventSessionHandling {
    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut {
        session?.shortcut ?? configuration.shortcutProvider()
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
        if !openedSession || configuration.movesSelectionOnNewSession {
            if var session = session {
                configuration.moveSelection(&session, backward ? -1 : 1)
                self.session = session
            }
        }
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if configuration.shouldCommit(activeSession), let selectedItem = activeSession.selectedItem {
            let committed = configuration.commitSelection(activeSession, selectedItem)
            if !committed {
                configuration.dismissPanel()
                session = nil
            }
        } else {
            configuration.dismissPanel()
            session = nil
        }
    }

    func switcherCancelActiveSession() {
        configuration.dismissPanel()
        session = nil
    }
}
