import Core
import Foundation

protocol WindowSwitcherSessionProtocol: SwitcherSession where Selection == Int {
    var startingWindowID: Int? { get }
    var selectedWindowID: Int? { get set }
    var spaceGroups: [SpaceWindowGroup] { get }
    var flatEntries: [WindowEntry] { get }
}

extension WindowSwitcherSessionProtocol {
    var selectedItem: Int? {
        get { selectedWindowID }
        set { selectedWindowID = newValue }
    }

    var didChangeSelection: Bool {
        selectedWindowID != nil && selectedWindowID != startingWindowID
    }
}

struct WindowSwitcherSession: WindowSwitcherSessionProtocol {
    let startingWindowID: Int?
    var selectedWindowID: Int?
    let shortcut: SpaceSwitcherShortcut
    let spaceGroups: [SpaceWindowGroup]
    let flatEntries: [WindowEntry]
    let trigger: SwitcherSessionTrigger
}

enum WindowSwitcherSelection {
    static func nextWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.first
        }
        return orderedWindowIDs[(index + 1) % orderedWindowIDs.count]
    }

    static func previousWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.last
        }
        return orderedWindowIDs[(index - 1 + orderedWindowIDs.count) % orderedWindowIDs.count]
    }
}
