import AppKit
import Core
import SwiftUI

final class SpaceSwitcherPanelManager {
    var panelPair: (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>)?

    func present(
        snapshot: SpaceSwitcherSnapshot,
        onSelect: @escaping (Int) -> Void,
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

    private func ensurePanel(
        for snapshot: SpaceSwitcherSnapshot,
        onSelect: @escaping (Int) -> Void,
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
            rootView: SpaceSwitcherView(
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
        with snapshot: SpaceSwitcherSnapshot,
        onSelect: @escaping (Int) -> Void,
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
        panelPair.hosting.rootView = SpaceSwitcherView(
            snapshot: snapshot,
            onSelect: onSelect,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
        resizePanel(for: snapshot)
    }

    private func resizePanel(for snapshot: SpaceSwitcherSnapshot) {
        guard let panelPair else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let width = min(max(screenFrame.width * 0.32, 420), 560)
        let rowHeight: CGFloat = 38
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let visibleRows = max(snapshot.items.count, 1)
        let desiredHeight = headerHeight + CGFloat(visibleRows) * rowHeight + listPadding
        let height = min(desiredHeight, max(screenFrame.height - 80, headerHeight + rowHeight + listPadding))
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }
}
