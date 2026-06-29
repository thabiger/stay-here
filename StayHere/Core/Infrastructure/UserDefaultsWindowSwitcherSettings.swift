import Foundation

public final class UserDefaultsWindowSwitcherSettings: WindowSwitcherSettings {
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

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var windowSwitcherEnabled: Bool {
        get {
            if defaults.object(forKey: Key.windowSwitcherEnabled) != nil {
                return defaults.bool(forKey: Key.windowSwitcherEnabled)
            }
            return Defaults.windowSwitcherEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherEnabled)
        }
    }

    public var windowSwitcherShortcutText: String {
        get {
            if let stored = defaults.string(forKey: Key.windowSwitcherShortcut),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return Defaults.windowSwitcherShortcut
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.windowSwitcherShortcut)
        }
    }

    public var windowSwitcherTitleFormat: WindowSwitcherTitleFormat {
        get {
            if let stored = defaults.string(forKey: Key.windowSwitcherTitleFormat),
               let format = WindowSwitcherTitleFormat(rawValue: stored) {
                return format
            }
            return Defaults.windowSwitcherTitleFormat
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.windowSwitcherTitleFormat)
        }
    }

    public var windowSwitcherShowMinimizedWindows: Bool {
        get {
            defaults.object(forKey: Key.windowSwitcherShowMinimizedWindows) != nil
                ? defaults.bool(forKey: Key.windowSwitcherShowMinimizedWindows)
                : Defaults.windowSwitcherShowMinimizedWindows
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherShowMinimizedWindows)
        }
    }

    public var windowSwitcherShowHiddenWindows: Bool {
        get {
            defaults.object(forKey: Key.windowSwitcherShowHiddenWindows) != nil
                ? defaults.bool(forKey: Key.windowSwitcherShowHiddenWindows)
                : Defaults.windowSwitcherShowHiddenWindows
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherShowHiddenWindows)
        }
    }
}
