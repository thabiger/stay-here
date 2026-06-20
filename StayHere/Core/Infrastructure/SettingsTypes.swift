import Foundation
import CoreGraphics

public enum AppearanceMode: String, CaseIterable, Equatable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

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
}

public enum HotCorner: String, CaseIterable, Hashable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var displayName: String {
        switch self {
        case .topLeft:
            return "Top Left"
        case .topRight:
            return "Top Right"
        case .bottomLeft:
            return "Bottom Left"
        case .bottomRight:
            return "Bottom Right"
        }
    }
}

public enum HotCornerAction: String, CaseIterable, Hashable {
    case none
    case spaceSwitcher
    case windowSwitcher
    case allSpacesWindowSwitcher

    public var displayName: String {
        switch self {
        case .none:
            return "Off"
        case .spaceSwitcher:
            return "Space Switcher"
        case .windowSwitcher:
            return "Window Switcher"
        case .allSpacesWindowSwitcher:
            return "All Spaces Window Switcher"
        }
    }
}

public struct SpaceSwitcherShortcut: Equatable {
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags

    public init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        let modifierParts: [String] = [
            modifiers.contains(.maskControl) ? "control" : nil,
            modifiers.contains(.maskAlternate) ? "option" : nil,
            modifiers.contains(.maskShift) ? "shift" : nil,
            modifiers.contains(.maskCommand) ? "command" : nil
        ].compactMap { $0 }

        return (modifierParts + [Self.keyName(for: keyCode)]).joined(separator: "+")
    }

    public static func keyName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 48: return "tab"
        case 49: return "space"
        case 50: return "backtick"
        case 36: return "return"
        case 53: return "escape"
        case 51: return "delete"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default:
            return "key\(keyCode)"
        }
    }

    public static func parse(_ text: String) -> SpaceSwitcherShortcut? {
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
        guard let keyCode = ShortcutKeyCodes.keyCode(for: keyToken) else { return nil }
        return SpaceSwitcherShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}

public enum ShortcutKeyCodes {
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

public enum SingleWindowAppBundleIDList {
    public static let defaultBundleIDs: [String] = [
        "com.apple.Notes",
        "com.openai.codex"
    ]

    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    public static func serialize(_ bundleIDs: [String]) -> String {
        var seen = Set<String>()
        return bundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }
}
