import AppKit

struct WindowEntry {
    let windowID: Int
    let pid: pid_t
    let appName: String
    let windowTitle: String?
    let icon: NSImage
}

struct WindowSpaceContext: Equatable {
    let spaceID: Int
    let desktopNumber: Int?
}

struct SpaceWindowGroup {
    let spaceID: Int
    let spaceLabel: String
    let entries: [WindowEntry]
}

struct WindowSwitcherItem: Identifiable {
    let id: Int
    let icon: NSImage
    let title: String
    let entry: WindowEntry
    let isSelected: Bool
}

struct WindowSwitcherSpaceGroup: Identifiable {
    let id: Int
    let spaceLabel: String
    let items: [WindowSwitcherItem]
}

struct WindowSwitcherSnapshot {
    let spaceGroups: [WindowSwitcherSpaceGroup]
    let title: String
    let subtitle: String
    let emptyMessage: String
    let iconName: String
    let showSpaceLabels: Bool
}

enum WindowSwitcherMode {
    case currentSpace
    case allSpaces
}

/// Whether a listing passed to the recency tracker covers all windows.
/// Complete listings (all spaces) are authoritative: IDs absent from them
/// are stale and pruned. Subset listings (current space) must preserve
/// recency for windows they do not contain.
enum WindowRecencyScope {
    case subset
    case complete
}

extension WindowSwitcherMode {
    var recencyScope: WindowRecencyScope {
        switch self {
        case .currentSpace: .subset
        case .allSpaces: .complete
        }
    }
}
