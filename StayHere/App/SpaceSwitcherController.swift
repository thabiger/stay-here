import AppKit
import CoreGraphics
import Core
import SwiftUI

final class SpaceSwitcherController: SwitcherEventSessionHandling {
    private struct Session {
        let startingSpaceID: Int?
        var selectedSpaceID: Int?
        let shortcut: SpaceSwitcherShortcut

        var didChangeSelection: Bool {
            selectedSpaceID != nil && selectedSpaceID != startingSpaceID
        }
    }

    private let registry: SpaceRegistry
    private let switchToSpace: (Int) -> Void
    private let shortcutProvider: () -> SpaceSwitcherShortcut
    private let panelManager = SpaceSwitcherPanelManager()
    private lazy var eventSupport = SwitcherEventControllerSupport(
        handler: self,
        eventTapUnavailableLog: "space-switcher failed=event-tap-unavailable"
    )

    private var session: Session?

    var panelPair: (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var hasActiveSession: Bool { session != nil }

    init(
        settings: SettingsRepository,
        registry: SpaceRegistry,
        switchToSpace: @escaping (Int) -> Void,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil
    ) {
        self.registry = registry
        self.switchToSpace = switchToSpace
        self.shortcutProvider = shortcutProvider ?? {
            SpaceSwitcherShortcut.parse(settings.spaceSwitcherShortcutText)
                ?? SpaceSwitcherShortcut.parse("command+tab")
                ?? SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand])
        }
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

    private func ensureSession(using shortcut: SpaceSwitcherShortcut) {
        if session == nil {
            session = Session(
                startingSpaceID: registry.activeSpaceID,
                selectedSpaceID: registry.activeSpaceID,
                shortcut: shortcut
            )
        }
    }

    private func moveSelection(offset: Int) {
        guard var session else { return }
        let ordered = registry.switchableOrderedSpaceIDs()
        let currentSelection = session.selectedSpaceID ?? session.startingSpaceID
        let nextSelection = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
        session.selectedSpaceID = nextSelection
        self.session = session
    }

    private func commitSelection(_ spaceID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.dismiss()
            self.session = nil
            self.switchToSpace(spaceID)
        }
    }

    private func showPanel() {
        let snapshot = buildSnapshot()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.present(snapshot: snapshot) { [weak self] spaceID in
                self?.commitSelection(spaceID)
            }
        }
    }

    private func buildSnapshot() -> SpaceSwitcherSnapshot {
        let orderedIDs = registry.switchableOrderedSpaceIDs()
        let selectedID = session?.selectedSpaceID ?? registry.activeSpaceID
        let items = orderedIDs.map { id in
            let isEnabled = registry.isSwitchableSpace(id)
            return SpaceSwitcherItem(
                id: id,
                title: "\(registry.namespaceLabel(for: id))  \(registry.displayName(for: id))",
                isSelected: id == selectedID,
                isCurrent: id == registry.activeSpaceID,
                isEnabled: isEnabled
            )
        }
        return SpaceSwitcherSnapshot(items: items, title: "Space Switcher")
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
        ensureSession(using: shortcut)
        moveSelection(offset: backward ? -1 : 1)
        showPanel()
    }

    func switcherCommitOrDismissActiveSession() {
        guard let activeSession = session else { return }
        if activeSession.didChangeSelection, let selectedID = activeSession.selectedSpaceID {
            commitSelection(selectedID)
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
