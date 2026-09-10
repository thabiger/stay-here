import AppKit
import Core
import SwiftUI

final class WindowSwitcherPanelPresenter {
    private let panelManager = WindowSwitcherPanelManager()

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelManager.panelPair }
        set { panelManager.panelPair = newValue }
    }

    func present(
        snapshot: WindowSwitcherSnapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        updateInfo: UpdateInfo? = nil,
        onOpenUpdate: (() -> Void)? = nil
    ) {
        panelManager.present(
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
    }

    func dismiss() {
        panelManager.dismiss()
    }

    func release() {
        panelManager.release()
    }
}

extension WindowSwitcherPanelPresenter: SwitcherPanelPresenting {
    func presentSnapshot(_ snapshot: WindowSwitcherSnapshot, actions: SwitcherPanelActions<Int>, updateInfo: UpdateInfo?) {
        present(
            snapshot: snapshot,
            onSelect: { entry in actions.onSelect(entry.windowID) },
            onFocusLost: actions.onFocusLost,
            onCommit: actions.onCommit,
            onCancel: actions.onCancel,
            onMoveUp: actions.onMoveUp,
            onMoveDown: actions.onMoveDown,
            updateInfo: updateInfo,
            onOpenUpdate: actions.onOpenUpdate
        )
    }

    func dismissPanel() { dismiss() }

    func releasePanel() { release() }
}
