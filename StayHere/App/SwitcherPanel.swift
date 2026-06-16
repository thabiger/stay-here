import AppKit

final class SwitcherPanel: NSPanel {
    var onFocusLost: (() -> Void)?

    override func resignKey() {
        super.resignKey()
        onFocusLost?()
    }
}
