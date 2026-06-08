import AppKit
import Core

final class HUDController {
    private let settings: SettingsRepository
    private let appearanceManager: AppearanceManager
    private let hudWidth: CGFloat = 560
    private let cornerRadius: CGFloat = 18
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 18
    private let textFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private var windowPair: (window: NSWindow, label: NSTextField)?
    private var hideTask: DispatchWorkItem?

    init(settings: SettingsRepository, appearanceManager: AppearanceManager) {
        self.settings = settings
        self.appearanceManager = appearanceManager
    }

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
        let duration = settings.hudDisplayDuration
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
            applyAppearance(to: existing.window, label: existing.label)
            return
        }
        windowPair = makeWindow(layout: layout)
    }

    private func makeWindow(layout: HUDLayout) -> (window: NSWindow, label: NSTextField) {
        let win = NSWindow(contentRect: layout.windowFrame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.backgroundColor = .clear
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
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.addSubview(text)
        win.contentView = content
        applyAppearance(to: win, label: text)

        return (win, text)
    }

    private func applyAppearance(to window: NSWindow, label: NSTextField) {
        let appearance = appearanceManager.currentAppearance
        window.appearance = appearance
        window.contentView?.appearance = appearance
        label.appearance = appearance
        window.backgroundColor = .clear
        window.contentView?.layer?.cornerRadius = cornerRadius
        window.contentView?.layer?.cornerCurve = .continuous
        window.contentView?.layer?.masksToBounds = true
        window.contentView?.layer?.borderWidth = 1
        if appearanceManager.currentModeIsDark {
            window.contentView?.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.94).cgColor
            window.contentView?.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            label.textColor = .white
        } else {
            window.contentView?.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 0.94).cgColor
            window.contentView?.layer?.borderColor = NSColor.black.withAlphaComponent(0.10).cgColor
            label.textColor = .black
        }
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
