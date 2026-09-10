import Foundation

public final class UserDefaultsWindowSwitcherSettings: SettingsBackingStore, WindowSwitcherSettings {
    private enum Key {
        static let windowSwitcherEnabled = "windowSwitcher.enabled"
        static let windowSwitcherShortcut = "windowSwitcher.shortcut"
        static let windowSwitcherTitleFormat = "windowSwitcher.titleFormat"
        static let windowSwitcherShowMinimizedWindows = "windowSwitcher.showMinimizedWindows"
        static let windowSwitcherShowHiddenWindows = "windowSwitcher.showHiddenWindows"
    }

    private enum Defaults {
        static let windowSwitcherShortcut = "command+`"
        static let windowSwitcherEnabled: Bool = true
        static let windowSwitcherTitleFormat: WindowSwitcherTitleFormat = .appNameOnly
        static let windowSwitcherShowMinimizedWindows: Bool = false
        static let windowSwitcherShowHiddenWindows: Bool = false
    }

    public var windowSwitcherEnabled: Bool {
        get { defaults[setting: Key.windowSwitcherEnabled, default: Defaults.windowSwitcherEnabled] }
        set { defaults[setting: Key.windowSwitcherEnabled, default: Defaults.windowSwitcherEnabled] = newValue }
    }

    public var windowSwitcherShortcutText: String {
        get { defaults[settingTrimmed: Key.windowSwitcherShortcut, default: Defaults.windowSwitcherShortcut] }
        set { defaults[settingTrimmed: Key.windowSwitcherShortcut, default: Defaults.windowSwitcherShortcut] = newValue }
    }

    public var windowSwitcherTitleFormat: WindowSwitcherTitleFormat {
        get { defaults[setting: Key.windowSwitcherTitleFormat, default: Defaults.windowSwitcherTitleFormat] }
        set { defaults[setting: Key.windowSwitcherTitleFormat, default: Defaults.windowSwitcherTitleFormat] = newValue }
    }

    public var windowSwitcherShowMinimizedWindows: Bool {
        get { defaults[setting: Key.windowSwitcherShowMinimizedWindows, default: Defaults.windowSwitcherShowMinimizedWindows] }
        set { defaults[setting: Key.windowSwitcherShowMinimizedWindows, default: Defaults.windowSwitcherShowMinimizedWindows] = newValue }
    }

    public var windowSwitcherShowHiddenWindows: Bool {
        get { defaults[setting: Key.windowSwitcherShowHiddenWindows, default: Defaults.windowSwitcherShowHiddenWindows] }
        set { defaults[setting: Key.windowSwitcherShowHiddenWindows, default: Defaults.windowSwitcherShowHiddenWindows] = newValue }
    }
}
