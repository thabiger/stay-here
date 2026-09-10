import Foundation

public final class UserDefaultsSpaceSwitcherSettings: SettingsBackingStore, SpaceSwitcherSettings {
    private enum Key {
        static let spaceSwitcherEnabled = "spaceSwitcher.enabled"
        static let spaceSwitcherShortcut = "spaceSwitcher.shortcut"
    }

    private enum Defaults {
        static let spaceSwitcherShortcut = "command+tab"
        static let spaceSwitcherEnabled: Bool = true
    }

    public var spaceSwitcherEnabled: Bool {
        get { defaults[setting: Key.spaceSwitcherEnabled, default: Defaults.spaceSwitcherEnabled] }
        set { defaults[setting: Key.spaceSwitcherEnabled, default: Defaults.spaceSwitcherEnabled] = newValue }
    }

    public var spaceSwitcherShortcutText: String {
        get { defaults[settingTrimmed: Key.spaceSwitcherShortcut, default: Defaults.spaceSwitcherShortcut] }
        set { defaults[settingTrimmed: Key.spaceSwitcherShortcut, default: Defaults.spaceSwitcherShortcut] = newValue }
    }
}
