import Foundation

public struct MissionControlShortcutCheck {
    private struct Requirement: Equatable {
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
        public let itemStatuses: [ItemStatus]

        public var missingDescriptions: [String] {
            itemStatuses.compactMap { $0.isSatisfied ? nil : $0.issueDescription }
        }

        public var isSatisfied: Bool {
            itemStatuses.allSatisfy(\.isSatisfied)
        }

        public var warningMessage: String? {
            guard !isSatisfied else { return nil }
            return "Space Switcher needs Mission Control shortcuts enabled: Control+1 through Control+9."
        }
    }

    public struct ItemStatus: Equatable {
        public let displayName: String
        public let isSatisfied: Bool
        public let issueDescription: String?
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
        Requirement(id: 124, name: "Desktop 7", keyCode: 26),
        Requirement(id: 125, name: "Desktop 8", keyCode: 28),
        Requirement(id: 126, name: "Desktop 9", keyCode: 25),
    ]

    public static func check(defaults: UserDefaults = .standard, preferencesURL: URL? = nil) -> Result {
        let hotKeys = loadHotKeys(defaults: defaults, preferencesURL: preferencesURL) ?? [:]
        let requirementStatuses = requiredShortcuts.map { requirementStatus(for: $0, hotKeys: hotKeys) }

        return Result(itemStatuses: [aggregateStatus(for: requirementStatuses)])
    }

    private static func aggregateStatus(for requirementStatuses: [RequirementStatus]) -> ItemStatus {
        let failingRequirements = requirementStatuses.compactMap { status in
            status.isSatisfied ? nil : status.requirement.name
        }
        let isSatisfied = failingRequirements.isEmpty
        let issueDescription = isSatisfied
            ? nil
            : "Mission Control shortcuts Control+1 through Control+9 are not fully enabled"

        return ItemStatus(
            displayName: "Mission Control shortcuts: Control+1 through Control+9",
            isSatisfied: isSatisfied,
            issueDescription: issueDescription
        )
    }

    private static func requirementStatus(for requirement: Requirement, hotKeys: [String: Any]) -> RequirementStatus {
        guard let entry = hotKeys[String(requirement.id)] as? [String: Any] else {
            return RequirementStatus(requirement: requirement, isSatisfied: false)
        }
        guard isEnabled(entry),
              let parameters = parameters(entry),
              parameters.count >= 3,
              intValue(parameters[1]) == requirement.keyCode,
              intValue(parameters[2]) == requiredModifierMask else {
            return RequirementStatus(requirement: requirement, isSatisfied: false)
        }
        return RequirementStatus(requirement: requirement, isSatisfied: true)
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

    private struct RequirementStatus {
        let requirement: Requirement
        let isSatisfied: Bool
    }
}
