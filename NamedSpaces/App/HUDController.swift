import AppKit

final class HUDController {
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 72
    private var windowPair: (window: NSWindow, label: NSTextField)?
    private var hideTask: DispatchWorkItem?

    func show(name: String) {
        ensureWindow()
        guard let pair = windowPair else { return }
        pair.label.stringValue = name
        pair.window.alphaValue = 1
        pair.window.orderFrontRegardless()

        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let pair = self?.windowPair else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                pair.window.animator().alphaValue = 0
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func ensureWindow() {
        let frame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let existing = windowPair {
            existing.window.setFrame(hudRect(for: frame), display: true)
            return
        }
        windowPair = makeWindow(for: frame)
    }

    private func makeWindow(for frame: NSRect) -> (window: NSWindow, label: NSTextField) {
        let rect = hudRect(for: frame)
        let win = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.85)
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: 16, y: 20, width: hudWidth - 32, height: 30)
        text.alignment = .center
        text.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        text.textColor = .white

        let content = NSView(frame: NSRect(origin: .zero, size: rect.size))
        content.addSubview(text)
        win.contentView = content

        return (win, text)
    }

    private func hudRect(for frame: NSRect) -> NSRect {
        return NSRect(
            x: frame.midX - hudWidth / 2,
            y: frame.maxY - hudHeight - 56,
            width: hudWidth,
            height: hudHeight
        )
    }
}
