import CoreGraphics

public protocol CGEventTapClient: AnyObject {
    func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>?
    var hasActiveSession: Bool { get }
    var handlesKeyboardEvents: Bool { get }
    var handlesMouseEvents: Bool { get }
    var keyboardShortcutKeyCodes: Set<CGKeyCode> { get }
}

public extension CGEventTapClient {
    var keyboardShortcutKeyCodes: Set<CGKeyCode> { [] }
}
