import AppKit
import Core

/// Encapsulates the logic for propagating the current appearance
/// (light/dark/system) to the status bar menu, its items, and the
/// status item button.
@MainActor
struct StatusBarAppearanceApplier {
    private let settings: AppearanceSettings
    private let appearanceManager: AppearanceManager

    init(settings: AppearanceSettings, appearanceManager: AppearanceManager) {
        self.settings = settings
        self.appearanceManager = appearanceManager
    }

    /// Sets the appearance on the given menu, all its item views
    /// and submenus, and the status item button. Also updates the
    /// button's title to match the current appearance mode.
    func applyAppearance(to menu: NSMenu, statusItemButton: NSButton?, title: String) {
        let appearance = appearanceManager.currentAppearance
        menu.appearance = appearance
        for item in menu.items {
            item.view?.appearance = appearance
            (item.view as? SpaceMenuRowView)?.applyAppearance(appearance)
            item.submenu?.appearance = appearance
        }
        statusItemButton?.appearance = appearance
        updateStatusItemTitle(for: statusItemButton, title: title)
    }

    private func updateStatusItemTitle(for button: NSButton?, title: String) {
        guard let button else { return }
        if settings.appearanceMode == .light {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.menuBarFont(ofSize: 0)
                ]
            )
        } else {
            button.title = title
        }
    }
}
