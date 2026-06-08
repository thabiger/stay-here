import AppKit
import SwiftUI

final class WindowSwitcherPanelManager {
    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)?

    func present(snapshot: WindowSwitcherSnapshot, onSelect: @escaping (WindowEntry) -> Void) {
        ensurePanel(for: snapshot, onSelect: onSelect)
        updatePanel(with: snapshot, onSelect: onSelect)
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

    private func ensurePanel(for snapshot: WindowSwitcherSnapshot, onSelect: @escaping (WindowEntry) -> Void) {
        guard panelPair == nil else { return }

        let window = NSPanel(
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

        let hosting = NSHostingController(
            rootView: WindowSwitcherView(snapshot: snapshot, onSelect: onSelect)
        )
        window.contentViewController = hosting
        window.ignoresMouseEvents = false

        panelPair = (window, hosting)
        resizePanel(for: snapshot)
    }

    private func updatePanel(with snapshot: WindowSwitcherSnapshot, onSelect: @escaping (WindowEntry) -> Void) {
        guard let panelPair else { return }
        panelPair.hosting.rootView = WindowSwitcherView(snapshot: snapshot, onSelect: onSelect)
        resizePanel(for: snapshot)
    }

    private func resizePanel(for snapshot: WindowSwitcherSnapshot) {
        guard let panelPair else { return }
        let width: CGFloat = 560
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let height = WindowSwitcherController.panelHeight(itemCount: snapshot.items.count, screenHeight: screenFrame.height)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }
}
