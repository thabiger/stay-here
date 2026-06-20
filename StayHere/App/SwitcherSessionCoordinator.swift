import AppKit
import CoreGraphics
import Core
import Foundation

final class SwitcherSessionCoordinator<Session: SwitcherSession, Snapshot, Selection>
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
    private let shortcutProvider: () -> SpaceSwitcherShortcut
    private let movesSelectionOnNewSession: Bool
    private let buildSession: BuildSession
    private let moveSelection: MoveSelection
    private let buildSnapshot: BuildSnapshot
    private let itemAtPosition: ItemAtPosition
    private let shouldCommit: ShouldCommit
    private let commitSelection: CommitSelection
    private let presentSnapshot: PresentSnapshot
    private let dismissPanel: DismissPanel
    private let releasePanel: ReleasePanel

    init(
        shortcutProvider: @escaping () -> SpaceSwitcherShortcut,
        movesSelectionOnNewSession: Bool,
        buildSession: @escaping BuildSession,
        moveSelection: @escaping MoveSelection,
        buildSnapshot: @escaping BuildSnapshot,
        itemAtPosition: @escaping ItemAtPosition,
        shouldCommit: @escaping ShouldCommit,
        commitSelection: @escaping CommitSelection,
        presentSnapshot: @escaping PresentSnapshot,
        dismissPanel: @escaping DismissPanel,
        releasePanel: @escaping ReleasePanel
    ) {
        self.shortcutProvider = shortcutProvider
        self.movesSelectionOnNewSession = movesSelectionOnNewSession
        self.buildSession = buildSession
        self.moveSelection = moveSelection
        self.buildSnapshot = buildSnapshot
        self.itemAtPosition = itemAtPosition
        self.shouldCommit = shouldCommit
        self.commitSelection = commitSelection
        self.presentSnapshot = presentSnapshot
        self.dismissPanel = dismissPanel
        self.releasePanel = releasePanel
    }

    var hasActiveSession: Bool { session != nil }

    var testSession: Session? { session }

    func start() {}

    func stop() {
        releasePanel()
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
        guard let item = itemAtPosition(session, position) else { return }
        let committed = commitSelection(session, item)
        if !committed {
            dismissPanel()
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
            moveSelection(&session, offset)
            self.session = session
        }
        showPanel()
    }

    private func ensureSession(using shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Bool {
        guard session == nil else { return false }
        session = buildSession(shortcut, trigger)
        return session != nil
    }

    private func showPanel() {
        let enablePanelKeyboardHandling = session?.trigger == .explicit
        let snapshot = buildSnapshot(session)
        let updateInfo = currentUpdateInfo
        let onOpenUpdate = self.onOpenUpdate
        presentSnapshot(
            snapshot,
            { [weak self] selection in
                let committed = self?.commitSelection(self?.session, selection) ?? false
                if !committed {
                    self?.dismissPanel()
                    self?.session = nil
                }
            },
            { [weak self] in
                self?.switcherCancelActiveSession()
            },
            enablePanelKeyboardHandling ? { [weak self] in
                self?.commitSwitcherSelection()
            } : nil,
            enablePanelKeyboardHandling ? { [weak self] in
                self?.closeSwitcher()
            } : nil,
            enablePanelKeyboardHandling ? { [weak self] in
                self?.moveSelectionBackward()
            } : nil,
            enablePanelKeyboardHandling ? { [weak self] in
                self?.moveSelectionForward()
            } : nil,
            updateInfo,
            onOpenUpdate
        )
    }
}

extension SwitcherSessionCoordinator: SwitcherEventSessionHandling {
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
        if !openedSession || movesSelectionOnNewSession {
            if var session = session {
                moveSelection(&session, backward ? -1 : 1)
                self.session = session
            }
        }
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if shouldCommit(activeSession), let selectedItem = activeSession.selectedItem {
            let committed = commitSelection(activeSession, selectedItem)
            if !committed {
                dismissPanel()
                session = nil
            }
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
