import Foundation
import CoreGraphics

public enum WindowSwitcherTitleFormat: String, CaseIterable, Hashable {
    case appNameOnly
    case appNameAndWindowTitle

    public var displayName: String {
        switch self {
        case .appNameOnly:
            return "App name only"
        case .appNameAndWindowTitle:
            return "App name: window title"
        }
    }
}

public final class WindowSwitcherSettings {
    public static let shared = WindowSwitcherSettings()

    private let defaults: UserDefaults
    private let key = "windowSwitcher.shortcut"
    private let enabledKey = "windowSwitcher.enabled"
    private let titleFormatKey = "windowSwitcher.titleFormat"
    private let showMinimizedWindowsKey = "windowSwitcher.showMinimizedWindows"
    private let showHiddenWindowsKey = "windowSwitcher.showHiddenWindows"
    private let defaultShortcutText = "command+`"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var shortcutText: String {
        get {
            if let stored = defaults.string(forKey: key), !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return defaultShortcutText
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
        }
    }

    public var isEnabled: Bool {
        get {
            if defaults.object(forKey: enabledKey) != nil {
                return defaults.bool(forKey: enabledKey)
            }

            return true
        }
        set {
            defaults.set(newValue, forKey: enabledKey)
        }
    }

    public var titleFormat: WindowSwitcherTitleFormat {
        get {
            if let stored = defaults.string(forKey: titleFormatKey),
               let format = WindowSwitcherTitleFormat(rawValue: stored) {
                return format
            }

            return .appNameOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: titleFormatKey)
        }
    }

    public var shortcut: SpaceSwitcherShortcut {
        Self.parseShortcut(shortcutText) ?? Self.parseShortcut(defaultShortcutText) ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
    }

    public var showMinimizedWindows: Bool {
        get {
            defaults.object(forKey: showMinimizedWindowsKey) != nil
                ? defaults.bool(forKey: showMinimizedWindowsKey)
                : false
        }
        set {
            defaults.set(newValue, forKey: showMinimizedWindowsKey)
        }
    }

    public var showHiddenWindows: Bool {
        get {
            defaults.object(forKey: showHiddenWindowsKey) != nil
                ? defaults.bool(forKey: showHiddenWindowsKey)
                : false
        }
        set {
            defaults.set(newValue, forKey: showHiddenWindowsKey)
        }
    }

    public static func displayTitle(
        appName: String,
        windowTitle: String?,
        format: WindowSwitcherTitleFormat
    ) -> String {
        let trimmedWindowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard format == .appNameAndWindowTitle,
              !trimmedWindowTitle.isEmpty,
              trimmedWindowTitle != appName else {
            return appName
        }

        return "\(appName): \(trimmedWindowTitle)"
    }

    public static func parseShortcut(_ text: String) -> SpaceSwitcherShortcut? {
        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: "+").map(String.init).filter { !$0.isEmpty }
        guard let keyToken = parts.last else { return nil }

        var modifiers = CGEventFlags()
        for token in parts.dropLast() {
            switch token {
            case "option", "alt":
                modifiers.insert(.maskAlternate)
            case "shift":
                modifiers.insert(.maskShift)
            case "control", "ctrl":
                modifiers.insert(.maskControl)
            case "command", "cmd":
                modifiers.insert(.maskCommand)
            default:
                return nil
            }
        }

        guard !modifiers.isEmpty else { return nil }
        guard let keyCode = keyCode(for: keyToken) else { return nil }
        return SpaceSwitcherShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    public static func keyCode(for token: String) -> CGKeyCode? {
        switch token {
        case "tab": return 48
        case "space": return 49
        case "`", "backtick", "grave", "tilde": return 50
        case "return", "enter": return 36
        case "escape", "esc": return 53
        case "delete", "backspace": return 51
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "0": return 29
        case "-": return 27
        case "=": return 24
        case "o": return 31
        case "u": return 32
        case "[": return 33
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "'": return 39
        case "k": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "n": return 45
        case "m": return 46
        case ".": return 47
        default:
            return nil
        }
    }
}
