import Foundation

public final class UserDefaultsSpaceSwitcherSettings: SpaceSwitcherSettings {
    private enum Key {
        static let spaceSwitcherEnabled = "spaceSwitcher.enabled"
        static let spaceSwitcherShortcut = "spaceSwitcher.shortcut"
    }

    private enum Defaults {
        static let spaceSwitcherShortcut = "command+tab"
        static let spaceSwitcherEnabled: Bool = true
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var spaceSwitcherEnabled: Bool {
        get {
            if defaults.object(forKey: Key.spaceSwitcherEnabled) != nil {
                return defaults.bool(forKey: Key.spaceSwitcherEnabled)
            }
            return Defaults.spaceSwitcherEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.spaceSwitcherEnabled)
        }
    }

    public var spaceSwitcherShortcutText: String {
        get {
            if let stored = defaults.string(forKey: Key.spaceSwitcherShortcut),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return Defaults.spaceSwitcherShortcut
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.spaceSwitcherShortcut)
        }
    }
}
