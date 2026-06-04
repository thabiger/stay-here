import AppKit

final class HUDController {
    private let hudWidth: CGFloat = 560
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 18
    private let textFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private var windowPair: (window: NSWindow, label: NSTextField)?
    private var hideTask: DispatchWorkItem?

    func show(name: String) {
        show(message: name)
    }

    func show(message: String) {
        ensureWindow(for: message)
        guard let pair = windowPair else { return }
        pair.label.stringValue = message
        pair.window.alphaValue = 1
        pair.window.orderFrontRegardless()

        hideTask?.cancel()
        let duration = HUDSettings.shared.displayDuration
        let task = DispatchWorkItem { [weak self] in
            guard let pair = self?.windowPair else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                pair.window.animator().alphaValue = 0
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func ensureWindow(for message: String) {
        let frame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let layout = hudLayout(for: message, in: frame)
        if let existing = windowPair {
            existing.window.setFrame(layout.windowFrame, display: true)
            existing.label.frame = layout.textFrame
            existing.window.contentView?.frame = NSRect(origin: .zero, size: layout.windowFrame.size)
            return
        }
        windowPair = makeWindow(layout: layout)
    }

    private func makeWindow(layout: HUDLayout) -> (window: NSWindow, label: NSTextField) {
        let win = NSWindow(contentRect: layout.windowFrame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let text = NSTextField(labelWithString: "")
        text.frame = layout.textFrame
        text.alignment = .center
        text.font = textFont
        text.textColor = .labelColor
        text.isBezeled = false
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.usesSingleLineMode = false
        text.maximumNumberOfLines = 2
        text.lineBreakMode = .byWordWrapping

        let content = NSView(frame: NSRect(origin: .zero, size: layout.windowFrame.size))
        content.addSubview(text)
        win.contentView = content

        return (win, text)
    }

    private func hudLayout(for message: String, in frame: NSRect) -> HUDLayout {
        let availableWidth = hudWidth - horizontalPadding * 2
        let bounds = NSAttributedString(
            string: message,
            attributes: [.font: textFont]
        ).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textHeight = ceil(bounds.height)
        let windowHeight = textHeight + verticalPadding * 2
        let windowFrame = NSRect(
            x: frame.midX - hudWidth / 2,
            y: frame.maxY - windowHeight - 56,
            width: hudWidth,
            height: windowHeight
        )
        let textFrame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: availableWidth,
            height: textHeight
        )
        return HUDLayout(windowFrame: windowFrame, textFrame: textFrame)
    }
}

private struct HUDLayout {
    let windowFrame: NSRect
    let textFrame: NSRect
}
