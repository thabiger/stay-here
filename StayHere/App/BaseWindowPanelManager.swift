import AppKit
import Core
import SwiftUI

class BaseWindowPanelManager<Snapshot, Content: View> {
    var panelPair: (window: NSPanel, hosting: NSHostingController<Content>)?

    func present(
        snapshot: Snapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)? = nil,
        onCommit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        updateInfo: UpdateInfo? = nil,
        onOpenUpdate: (() -> Void)? = nil
    ) {
        ensurePanel(
            for: snapshot,
            onSelect: onSelect,
            onFocusLost: onFocusLost,
            onCommit: onCommit,
            onCancel: onCancel,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
        updatePanel(
            with: snapshot,
            onSelect: onSelect,
            onFocusLost: onFocusLost,
            onCommit: onCommit,
            onCancel: onCancel,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
        panelPair?.window.orderFrontRegardless()
        panelPair?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panelPair?.window.orderOut(nil)
    }

    func release() {
        dismiss()
        panelPair = nil
    }

    func makeRootView(
        snapshot: Snapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) -> Content {
        fatalError("Subclasses must override makeRootView")
    }

    func resizePanel(for snapshot: Snapshot) {
        fatalError("Subclasses must override resizePanel")
    }

    private func ensurePanel(
        for snapshot: Snapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)?,
        onCommit: (() -> Void)?,
        onCancel: (() -> Void)?,
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) {
        guard panelPair == nil else { return }

        let window = SwitcherPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.onFocusLost = onFocusLost
        window.onCommit = onCommit
        window.onCancel = onCancel
        window.onMoveUp = onMoveUp
        window.onMoveDown = onMoveDown

        let hosting = NSHostingController(
            rootView: makeRootView(
                snapshot: snapshot,
                onSelect: onSelect,
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        )
        window.contentViewController = hosting
        window.ignoresMouseEvents = false

        panelPair = (window, hosting)
        resizePanel(for: snapshot)
    }

    private func updatePanel(
        with snapshot: Snapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        onFocusLost: (() -> Void)?,
        onCommit: (() -> Void)?,
        onCancel: (() -> Void)?,
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) {
        guard let panelPair else { return }
        (panelPair.window as? SwitcherPanel)?.onFocusLost = onFocusLost
        (panelPair.window as? SwitcherPanel)?.onCommit = onCommit
        (panelPair.window as? SwitcherPanel)?.onCancel = onCancel
        (panelPair.window as? SwitcherPanel)?.onMoveUp = onMoveUp
        (panelPair.window as? SwitcherPanel)?.onMoveDown = onMoveDown
        panelPair.hosting.rootView = makeRootView(
            snapshot: snapshot,
            onSelect: onSelect,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
        resizePanel(for: snapshot)
    }
}
