import Foundation
import CoreGraphics
import Core

protocol SwitcherControlling: AnyObject, CGEventTapClient {
    var hasActiveSession: Bool { get }
    func handle(event: CGEvent) -> Unmanaged<CGEvent>?
    func start()
    func stop()
    func openSwitcher()
    func closeSwitcher()
    func moveSelectionForward()
    func moveSelectionBackward()
    func commitSwitcherSelection()
    func commitSelection(at position: Int)
    func cancelSession()
}

extension SpaceSwitcherController: @preconcurrency SwitcherControlling {}
extension WindowSwitcherController: @preconcurrency SwitcherControlling {}

extension SwitcherControlling {
    func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        handle(event: event)
    }

    var handlesKeyboardEvents: Bool { true }
    var handlesMouseEvents: Bool { false }
}
