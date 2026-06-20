import Core
import Foundation

enum SwitcherSessionTrigger {
    case keyboard
    case explicit
}

protocol SwitcherSession {
    associatedtype Selection
    var selectedItem: Selection? { get set }
    var shortcut: SpaceSwitcherShortcut { get }
    var trigger: SwitcherSessionTrigger { get }
    var didChangeSelection: Bool { get }
}

struct SpaceSwitcherSession: SwitcherSession {
    let startingSpaceID: Int?
    var selectedSpaceID: Int?
    let shortcut: SpaceSwitcherShortcut
    let trigger: SwitcherSessionTrigger

    var selectedItem: Int? {
        get { selectedSpaceID }
        set { selectedSpaceID = newValue }
    }

    var didChangeSelection: Bool {
        selectedSpaceID != nil && selectedSpaceID != startingSpaceID
    }
}
