import Foundation

public struct MissionControlShortcutCheck {
    public struct Requirement: Equatable {
        public let id: Int
        public let name: String
        public let keyCode: Int

        public init(id: Int, name: String, keyCode: Int) {
            self.id = id
            self.name = name
            self.keyCode = keyCode
        }
    }

    public struct Result: Equatable {
        public let missingDescriptions: [String]

        public var isSatisfied: Bool {
            missingDescriptions.isEmpty
        }

        public var warningMessage: String? {
            guard !isSatisfied else { return nil }
            return "Space Switcher needs Mission Control shortcuts enabled: Control+1 through Control+6. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control."
        }
    }

    private static let requiredModifierMask = 262144
    private static let symbolicHotKeysKey = "AppleSymbolicHotKeys"
    private static let symbolicHotKeysPlistPath = "Library/Preferences/com.apple.symbolichotkeys.plist"

    private static let requiredShortcuts: [Requirement] = [
        Requirement(id: 118, name: "Desktop 1", keyCode: 18),
        Requirement(id: 119, name: "Desktop 2", keyCode: 19),
        Requirement(id: 120, name: "Desktop 3", keyCode: 20),
        Requirement(id: 121, name: "Desktop 4", keyCode: 21),
        Requirement(id: 122, name: "Desktop 5", keyCode: 23),
        Requirement(id: 123, name: "Desktop 6", keyCode: 22),
    ]

    public static func check(defaults: UserDefaults = .standard, preferencesURL: URL? = nil) -> Result {
        let hotKeys = loadHotKeys(defaults: defaults, preferencesURL: preferencesURL) ?? [:]

        let missing = requiredShortcuts.compactMap { requirement -> String? in
            guard let entry = hotKeys[String(requirement.id)] as? [String: Any] else {
                return "\(requirement.name) is missing"
            }
            guard isEnabled(entry),
                  let parameters = parameters(entry),
                  parameters.count >= 3,
                  intValue(parameters[1]) == requirement.keyCode,
                  intValue(parameters[2]) == requiredModifierMask else {
                return "\(requirement.name) is not set to Control+\(displayDigit(for: requirement.keyCode))"
            }
            return nil
        }

        return Result(missingDescriptions: missing)
    }

    static func loadHotKeys(defaults: UserDefaults, preferencesURL: URL? = nil) -> [String: Any]? {
        if let hotKeys = defaults.dictionary(forKey: symbolicHotKeysKey) {
            return hotKeys
        }

        let url = preferencesURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(symbolicHotKeysPlistPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else {
            return nil
        }
        return root[symbolicHotKeysKey] as? [String: Any]
    }

    private static func isEnabled(_ entry: [String: Any]) -> Bool {
        if let enabled = entry["enabled"] as? NSNumber {
            return enabled.intValue == 1
        }
        if let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        return false
    }

    private static func parameters(_ entry: [String: Any]) -> [Any]? {
        guard let value = entry["value"] as? [String: Any] else { return nil }
        return value["parameters"] as? [Any]
    }

    private static func intValue(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func displayDigit(for keyCode: Int) -> String {
        switch keyCode {
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        default: return "?"
        }
    }
}
