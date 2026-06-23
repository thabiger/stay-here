import Core
import Foundation

/// Bundles the action callbacks passed to the panel's `presentSnapshot`.
struct SwitcherPanelActions<Selection> {
    var onSelect: (Selection) -> Void
    var onFocusLost: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onOpenUpdate: (() -> Void)?
}

struct SwitcherConfiguration<Session, Snapshot, Selection> {
    var shortcutProvider: () -> SpaceSwitcherShortcut
    var movesSelectionOnNewSession: Bool
    var buildSession: (SpaceSwitcherShortcut, SwitcherSessionTrigger) -> Session?
    var moveSelection: (inout Session, Int) -> Void
    var buildSnapshot: (Session?) -> Snapshot
    var itemAtPosition: (Session?, Int) -> Selection?
    var shouldCommit: (Session) -> Bool
    var commitSelection: (Session?, Selection) -> Bool
    var presentSnapshot: (Snapshot, SwitcherPanelActions<Selection>, UpdateInfo?) -> Void
    var dismissPanel: () -> Void
    var releasePanel: () -> Void

    init(
        shortcutProvider: @escaping () -> SpaceSwitcherShortcut,
        movesSelectionOnNewSession: Bool,
        buildSession: @escaping (SpaceSwitcherShortcut, SwitcherSessionTrigger) -> Session?,
        moveSelection: @escaping (inout Session, Int) -> Void,
        buildSnapshot: @escaping (Session?) -> Snapshot,
        itemAtPosition: @escaping (Session?, Int) -> Selection?,
        commitSelection: @escaping (Session?, Selection) -> Bool,
        presentSnapshot: @escaping (Snapshot, SwitcherPanelActions<Selection>, UpdateInfo?) -> Void,
        dismissPanel: @escaping () -> Void,
        releasePanel: @escaping () -> Void,
        shouldCommit: @escaping (Session) -> Bool = { _ in true }
    ) {
        self.shortcutProvider = shortcutProvider
        self.movesSelectionOnNewSession = movesSelectionOnNewSession
        self.buildSession = buildSession
        self.moveSelection = moveSelection
        self.buildSnapshot = buildSnapshot
        self.itemAtPosition = itemAtPosition
        self.shouldCommit = shouldCommit
        self.commitSelection = commitSelection
        self.presentSnapshot = presentSnapshot
        self.dismissPanel = dismissPanel
        self.releasePanel = releasePanel
    }
}
