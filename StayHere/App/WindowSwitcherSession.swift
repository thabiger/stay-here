import Core
import Foundation

enum SwitcherSessionTrigger {
    case keyboard
    case explicit
}

protocol WindowSwitcherSessionProtocol {
    var startingWindowID: Int? { get }
    var selectedWindowID: Int? { get set }
    var shortcut: SpaceSwitcherShortcut { get }
    var trigger: SwitcherSessionTrigger { get }
    var spaceGroups: [WindowListProvider.SpaceWindowGroup] { get }
    var flatEntries: [WindowEntry] { get }
}

extension WindowSwitcherSessionProtocol {
    var didChangeSelection: Bool {
        selectedWindowID != nil && selectedWindowID != startingWindowID
    }
}

struct WindowSwitcherSession: WindowSwitcherSessionProtocol {
    let startingWindowID: Int?
    var selectedWindowID: Int?
    let shortcut: SpaceSwitcherShortcut
    let spaceGroups: [WindowListProvider.SpaceWindowGroup]
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

    static func sessionOrder(fromRecentEntries entries: [WindowEntry]) -> [WindowEntry] {
        guard entries.count > 1 else { return entries }
        return [entries[1], entries[0]] + Array(entries.dropFirst(2))
    }

    static func recentOrder(fromSessionEntries entries: [WindowEntry], startingWindowID: Int?) -> [Int] {
        let ids = entries.map(\.windowID)
        guard let startingWindowID, ids.contains(startingWindowID) else { return ids }
        return [startingWindowID] + ids.filter { $0 != startingWindowID }
    }

    static func recordSelection(
        _ selectedWindowID: Int,
        in activeSession: (any WindowSwitcherSessionProtocol)?,
        recentWindowIDs: inout [Int]
    ) {
        guard let activeSession else {
            recentWindowIDs.removeAll { $0 == selectedWindowID }
            recentWindowIDs.insert(selectedWindowID, at: 0)
            return
        }

        let previousRecentIDs = Self.recentOrder(
            fromSessionEntries: activeSession.flatEntries,
            startingWindowID: activeSession.startingWindowID
        )
        var orderedIDs = [selectedWindowID]
        if let startingWindowID = activeSession.startingWindowID,
           startingWindowID != selectedWindowID {
            orderedIDs.append(startingWindowID)
        }
        orderedIDs += previousRecentIDs.filter { id in
            id != selectedWindowID && id != activeSession.startingWindowID
        }
        recentWindowIDs = orderedIDs
    }
}
