import Foundation

/// Groups all status bar menu action callbacks so they can be configured as one unit.
struct StatusBarActions {
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void
    let onCheckForUpdates: () -> Void
    let onOpenAvailableUpdate: () -> Void
    let onCopyState: () -> Void
    let onOpenLogs: () -> Void
    let onQuit: () -> Void
    let onSelectSpace: (Int) -> Void
    let onRenameSpace: (Int, String) -> Void
}
