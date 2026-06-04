import AppKit
import Core

enum AppearanceManager {
    static func applyCurrentMode(to windows: [NSWindow] = NSApp.windows) {
        apply(mode: AppearanceSettings.shared.mode, to: windows)
    }

    static func apply(mode: AppearanceMode, to windows: [NSWindow] = NSApp.windows) {
        let appearance = nsAppearance(for: mode)
        NSApp.appearance = appearance

        for window in windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.contentViewController?.view.appearance = appearance
        }
    }

    static func nsAppearance(for mode: AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
