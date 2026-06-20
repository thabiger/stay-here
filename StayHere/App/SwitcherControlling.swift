import Foundation

protocol SwitcherControlling: AnyObject {
    func openSwitcher()
    func closeSwitcher()
    func moveSelectionForward()
    func moveSelectionBackward()
    func commitSwitcherSelection()
    func commitSelection(at position: Int)
    var hasActiveSession: Bool { get }
}

extension SpaceSwitcherController: SwitcherControlling {}
extension WindowSwitcherController: SwitcherControlling {}
