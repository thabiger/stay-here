import CoreGraphics

public protocol CGEventTapClient: AnyObject {
    func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>?
    var hasActiveSession: Bool { get }
    var handlesKeyboardEvents: Bool { get }
    var handlesMouseEvents: Bool { get }
}
