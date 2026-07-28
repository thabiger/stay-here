import AppKit
import CoreGraphics
import Core
import SwiftUI

@MainActor
final class SpaceSwitcherController {
    private let registry: any SpaceRegistryProtocol
    private let switchToSpace: (Int) -> Void
    private let shortcutProvider: () -> SpaceSwitcherShortcut
    private let panelManager = SpaceSwitcherPanelManager()
    private lazy var coordinator: SwitcherSessionController<SpaceSwitcherSession, SpaceSwitcherSnapshot, Int> = SwitcherSessionController(
        delegate: self,
        panelPresenter: panelManager
    )

    var panelPair: (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    internal var hasActiveSession: Bool { coordinator.hasActiveSession }

    internal var testSessionSelectedSpaceID: Int? {
        coordinator.testSession?.selectedSpaceID
    }

    init(
        settings: SpaceSwitcherSettings,
        registry: any SpaceRegistryProtocol,
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

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        coordinator.setAvailableUpdate(updateInfo)
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        coordinator.setOnOpenUpdate(callback)
    }

    func start() {
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
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

    internal func cancelSession() {
        coordinator.cancelSession()
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
        coordinator.commitSwitcherSelection()
    }

    func commitSelection(at position: Int) {
        coordinator.commitSelection(at: position)
    }

    func closeSwitcher() {
        coordinator.closeSwitcher()
    }

    func buildSnapshot(for session: SpaceSwitcherSession?) -> SpaceSwitcherSnapshot {
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

    private func commitSpace(_ spaceID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelManager.dismiss()
            self.coordinator.closeSwitcher()
            self.switchToSpace(spaceID)
        }
    }
}

@MainActor
extension SpaceSwitcherController: @preconcurrency SwitcherSessionDelegate {
    var movesSelectionOnNewSession: Bool { true }

    func provideShortcut() -> SpaceSwitcherShortcut {
        shortcutProvider()
    }

    func buildSession(shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> SpaceSwitcherSession? {
        SpaceSwitcherSession(
            startingSpaceID: registry.activeSpaceID,
            selectedSpaceID: registry.activeSpaceID,
            shortcut: shortcut,
            trigger: trigger
        )
    }

    func moveSelection(in session: inout SpaceSwitcherSession, offset: Int) {
        let ordered = registry.switchableOrderedSpaceIDs()
        let currentSelection = session.selectedSpaceID ?? session.startingSpaceID
        let nextSelection = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
        session.selectedSpaceID = nextSelection
    }

    func item(at position: Int, in session: SpaceSwitcherSession?) -> Int? {
        let orderedIDs = registry.switchableOrderedSpaceIDs()
        guard position > 0, position <= orderedIDs.count else { return nil }
        return orderedIDs[position - 1]
    }

    func shouldCommit(_ session: SpaceSwitcherSession) -> Bool {
        session.trigger == .explicit || session.didChangeSelection
    }

    func commit(selection spaceID: Int, in session: SpaceSwitcherSession?) -> Bool {
        commitSpace(spaceID)
        return true
    }
}
