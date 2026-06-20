import AppKit
import Core

final class AppearanceManager {
    private let settings: AppearanceSettings

    init(settings: AppearanceSettings) {
        self.settings = settings
    }

    var currentAppearance: NSAppearance? {
        Self.nsAppearance(for: settings.appearanceMode)
    }

    var currentModeIsDark: Bool {
        let appearance = currentAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func applyCurrentMode(to windows: [NSWindow] = NSApp.windows) {
        apply(mode: settings.appearanceMode, to: windows)
    }

    func apply(mode: AppearanceMode, to windows: [NSWindow] = NSApp.windows) {
        let appearance = Self.nsAppearance(for: mode)
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
