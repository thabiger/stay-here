import AppKit

final class SwitcherPanel: NSPanel {
    var onFocusLost: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func resignKey() {
        super.resignKey()
        onFocusLost?()
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyPress(keyCode: event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }

    @discardableResult
    func handleKeyPress(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36:
            onCommit?()
            return true
        case 53:
            onCancel?()
            return true
        case 126:
            onMoveUp?()
            return true
        case 125:
            onMoveDown?()
            return true
        default:
            return false
        }
    }
}
