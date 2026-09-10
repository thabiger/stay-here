import Foundation

public final class UserDefaultsAllSpacesWindowSwitcherSettings: SettingsBackingStore, AllSpacesWindowSwitcherSettings {
    private enum Key {
        static let allSpacesWindowSwitcherEnabled = "allSpacesWindowSwitcher.enabled"
        static let allSpacesWindowSwitcherShortcut = "allSpacesWindowSwitcher.shortcut"
    }

    private enum Defaults {
        static let allSpacesWindowSwitcherShortcut = "command+shift+`"
        static let allSpacesWindowSwitcherEnabled: Bool = true
    }

    public var allSpacesWindowSwitcherEnabled: Bool {
        get { defaults[setting: Key.allSpacesWindowSwitcherEnabled, default: Defaults.allSpacesWindowSwitcherEnabled] }
        set { defaults[setting: Key.allSpacesWindowSwitcherEnabled, default: Defaults.allSpacesWindowSwitcherEnabled] = newValue }
    }

    public var allSpacesWindowSwitcherShortcutText: String {
        get { defaults[settingTrimmed: Key.allSpacesWindowSwitcherShortcut, default: Defaults.allSpacesWindowSwitcherShortcut] }
        set { defaults[settingTrimmed: Key.allSpacesWindowSwitcherShortcut, default: Defaults.allSpacesWindowSwitcherShortcut] = newValue }
    }
}
