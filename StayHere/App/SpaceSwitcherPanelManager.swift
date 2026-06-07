import AppKit
import SwiftUI

final class SpaceSwitcherPanelManager {
    var panelPair: (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>)?

    func present(snapshot: SpaceSwitcherSnapshot, onSelect: @escaping (Int) -> Void) {
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

    private func ensurePanel(for snapshot: SpaceSwitcherSnapshot, onSelect: @escaping (Int) -> Void) {
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
            rootView: SpaceSwitcherView(snapshot: snapshot, onSelect: onSelect)
        )
        window.contentViewController = hosting
        window.ignoresMouseEvents = false

        panelPair = (window, hosting)
        resizePanel(for: snapshot)
    }

    private func updatePanel(with snapshot: SpaceSwitcherSnapshot, onSelect: @escaping (Int) -> Void) {
        guard let panelPair else { return }
        panelPair.hosting.rootView = SpaceSwitcherView(snapshot: snapshot, onSelect: onSelect)
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
