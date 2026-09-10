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
