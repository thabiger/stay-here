import AppKit
import CoreGraphics
import Core
import SwiftUI

final class SpaceSwitcherController {
    private let registry: SpaceRegistry
    private let switchToSpace: (Int) -> Void
    private let shortcutProvider: () -> SpaceSwitcherShortcut
    private let panelManager = SpaceSwitcherPanelManager()
    private lazy var coordinator = SwitcherSessionCoordinator<
        SpaceSwitcherSession,
        SpaceSwitcherSnapshot,
        Int
    >(
        shortcutProvider: { [weak self] in
            self?.shortcutProvider() ?? SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand])
        },
        movesSelectionOnNewSession: true,
        buildSession: { [weak self] shortcut, trigger in
            guard let self else { return nil }
            return SpaceSwitcherSession(
                startingSpaceID: self.registry.activeSpaceID,
                selectedSpaceID: self.registry.activeSpaceID,
                shortcut: shortcut,
                trigger: trigger
            )
        },
        moveSelection: { [weak self] session, offset in
            guard let self else { return }
            let ordered = self.registry.switchableOrderedSpaceIDs()
            let currentSelection = session.selectedSpaceID ?? session.startingSpaceID
            let nextSelection = offset > 0
                ? SpaceCycling.nextSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
                : SpaceCycling.previousSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
            session.selectedSpaceID = nextSelection
        },
        buildSnapshot: { [weak self] session in
            self?.buildSnapshot(for: session) ?? SpaceSwitcherSnapshot(items: [], title: "Space Switcher")
        },
        itemAtPosition: { [weak self] _, position in
            guard let self else { return nil }
            let orderedIDs = self.registry.switchableOrderedSpaceIDs()
            guard position > 0, position <= orderedIDs.count else { return nil }
            return orderedIDs[position - 1]
        },
        shouldCommit: { session in
            session.trigger == .explicit || session.didChangeSelection
        },
        commitSelection: { [weak self] _, spaceID in
            self?.commitSpace(spaceID)
            return true
        },
        presentSnapshot: { [weak self] snapshot, onSelect, onFocusLost, onCommit, onCancel, onMoveUp, onMoveDown, updateInfo, onOpenUpdate in
            self?.panelManager.present(
                snapshot: snapshot,
                onSelect: onSelect,
                onFocusLost: onFocusLost,
                onCommit: onCommit,
                onCancel: onCancel,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        },
        dismissPanel: { [weak self] in
            self?.panelManager.dismiss()
        },
        releasePanel: { [weak self] in
            self?.panelManager.release()
        }
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

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        coordinator.setAvailableUpdate(updateInfo)
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        coordinator.setOnOpenUpdate(callback)
    }

    deinit {
        stop()
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

    private func buildSnapshot(for session: SpaceSwitcherSession?) -> SpaceSwitcherSnapshot {
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
