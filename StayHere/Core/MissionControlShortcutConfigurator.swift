import Foundation
import CoreFoundation

public enum MissionControlShortcutConfigurator {
    public struct Result: Equatable {
        public let changed: Bool
        public let isSatisfied: Bool
    }

    private static let domainName = "com.apple.symbolichotkeys"
    private static let symbolicHotKeysKey = "AppleSymbolicHotKeys"
    private static let requiredModifierMask = 262144
    private static let requiredShortcuts: [(id: Int, keyCode: Int)] = [
        (118, 18),
        (119, 19),
        (120, 20),
        (121, 21),
        (122, 23),
        (123, 22),
        (124, 26),
        (125, 28),
        (126, 25),
    ]

    @discardableResult
    public static func ensureControlNumberShortcutsEnabled(
        defaults: UserDefaults? = nil
    ) -> Result {
        let resolvedDefaults = defaults ?? UserDefaults(suiteName: domainName)
        guard let resolvedDefaults else {
            return Result(changed: false, isSatisfied: false)
        }

        var hotKeys = MissionControlShortcutCheck.loadHotKeys(defaults: resolvedDefaults) ?? [:]
        var changed = false

        for shortcut in requiredShortcuts {
            let key = String(shortcut.id)
            let expected: [String: Any] = [
                "enabled": 1,
                "value": [
                    "parameters": [65535, shortcut.keyCode, requiredModifierMask],
                    "type": "standard"
                ]
            ]

            if !entry(hotKeys[key], matches: shortcut.keyCode) {
                hotKeys[key] = expected
                changed = true
            }
        }

        if changed {
            resolvedDefaults.set(hotKeys, forKey: symbolicHotKeysKey)
            resolvedDefaults.synchronize()
            CFPreferencesAppSynchronize(domainName as CFString)
        }

        let result = MissionControlShortcutCheck.check(defaults: resolvedDefaults)
        return Result(changed: changed, isSatisfied: result.isSatisfied)
    }

    private static func entry(_ rawValue: Any?, matches keyCode: Int) -> Bool {
        guard let entry = rawValue as? [String: Any],
              let enabled = entry["enabled"] as? NSNumber,
              enabled.intValue == 1,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3,
              intValue(parameters[1]) == keyCode,
              intValue(parameters[2]) == requiredModifierMask else {
            return false
        }
        return true
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
}
