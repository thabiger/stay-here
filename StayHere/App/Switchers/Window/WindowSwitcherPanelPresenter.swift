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
