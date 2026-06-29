import Foundation

public final class UserDefaultsAllSpacesWindowSwitcherSettings: AllSpacesWindowSwitcherSettings {
    private enum Key {
        static let allSpacesWindowSwitcherEnabled = "allSpacesWindowSwitcher.enabled"
        static let allSpacesWindowSwitcherShortcut = "allSpacesWindowSwitcher.shortcut"
    }

    private enum Defaults {
        static let allSpacesWindowSwitcherShortcut = "command+shift+`"
        static let allSpacesWindowSwitcherEnabled: Bool = true
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var allSpacesWindowSwitcherEnabled: Bool {
        get {
            if defaults.object(forKey: Key.allSpacesWindowSwitcherEnabled) != nil {
                return defaults.bool(forKey: Key.allSpacesWindowSwitcherEnabled)
            }
            return Defaults.allSpacesWindowSwitcherEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.allSpacesWindowSwitcherEnabled)
        }
    }

    public var allSpacesWindowSwitcherShortcutText: String {
        get {
            if let stored = defaults.string(forKey: Key.allSpacesWindowSwitcherShortcut),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return Defaults.allSpacesWindowSwitcherShortcut
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.allSpacesWindowSwitcherShortcut)
        }
    }
}
