import Foundation

public struct MissionControlShortcutCheck {
    private struct Requirement: Equatable {
        let id: Int
        let name: String
        let keyCode: Int
    }

    public struct ItemStatus: Equatable {
        public let displayName: String
        public let isSatisfied: Bool
        public let issueDescription: String?
    }

    public struct Result: Equatable {
        public let itemStatuses: [ItemStatus]
        public let guidanceMessage: String

        public var missingDescriptions: [String] {
            itemStatuses.compactMap { $0.isSatisfied ? nil : $0.issueDescription }
        }

        public var isSatisfied: Bool {
            itemStatuses.allSatisfy(\.isSatisfied)
        }

        public var warningMessage: String? {
            isSatisfied ? nil : guidanceMessage
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
        Requirement(id: 124, name: "Desktop 7", keyCode: 26),
        Requirement(id: 125, name: "Desktop 8", keyCode: 28),
        Requirement(id: 126, name: "Desktop 9", keyCode: 25),
    ]

    public static func check(
        desktopCount: Int? = nil,
        defaults: UserDefaults = .standard,
        preferencesURL: URL? = nil,
        cgsBridge: any CGSBridgeProtocol
    ) -> Result {
        let hotKeys = loadHotKeys(
            defaults: defaults,
            preferencesURL: preferencesURL,
            preferPersistentStore: shouldPreferPersistentStore(defaults: defaults, preferencesURL: preferencesURL)
        ) ?? [:]
        let requiredRequirements = requirements(forDesktopCount: desktopCount ?? currentDesktopCount(cgsBridge: cgsBridge))
        let failingRequirements = requiredRequirements.filter { failureDescription(for: $0, hotKeys: hotKeys) != nil }
        let isSatisfied = failingRequirements.isEmpty
        let shortcutRangeDescription = shortcutRangeDescription(forDesktopCount: requiredRequirements.count)
        let issueDescription = isSatisfied
            ? nil
            : "Mission Control shortcuts \(shortcutRangeDescription) are not fully enabled"

        return Result(
            itemStatuses: [
                ItemStatus(
                    displayName: "Mission Control shortcuts: \(shortcutRangeDescription)",
                    isSatisfied: isSatisfied,
                    issueDescription: issueDescription
                )
            ],
            guidanceMessage: "Space Switcher needs Mission Control shortcuts enabled: \(shortcutRangeDescription). Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control."
        )
    }

    public static func checkShortcut(
        forDesktopIndex desktopIndex: Int,
        defaults: UserDefaults = .standard,
        preferencesURL: URL? = nil
    ) -> Result {
        guard let requirement = requirement(forDesktopIndex: desktopIndex) else {
            return Result(
                itemStatuses: [
                    ItemStatus(
                        displayName: "Desktop \(desktopIndex)",
                        isSatisfied: false,
                        issueDescription: "Desktop \(desktopIndex) is unsupported"
                    )
                ],
                guidanceMessage: "StayHere can switch only desktops 1 through 9 with Mission Control shortcuts."
            )
        }

        let hotKeys = loadHotKeys(
            defaults: defaults,
            preferencesURL: preferencesURL,
            preferPersistentStore: shouldPreferPersistentStore(defaults: defaults, preferencesURL: preferencesURL)
        ) ?? [:]
        let issueDescription = failureDescription(for: requirement, hotKeys: hotKeys)

        return Result(
            itemStatuses: [
                ItemStatus(
                    displayName: requirement.name,
                    isSatisfied: issueDescription == nil,
                    issueDescription: issueDescription
                )
            ],
            guidanceMessage: "Desktop \(desktopIndex) cannot be switched because Mission Control shortcut Control+\(desktopIndex) is disabled or changed. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control and enable \"Switch to Desktop \(desktopIndex)\"."
        )
    }

    static func loadHotKeys(
        defaults: UserDefaults,
        preferencesURL: URL? = nil,
        preferPersistentStore: Bool = false
    ) -> [String: Any]? {
        if preferPersistentStore,
           let hotKeys = readHotKeysFromPersistentStore(preferencesURL: preferencesURL) {
            return hotKeys
        }

        if let hotKeys = defaults.dictionary(forKey: symbolicHotKeysKey) {
            return hotKeys
        }

        if !preferPersistentStore,
           let hotKeys = readHotKeysFromPersistentStore(preferencesURL: preferencesURL) {
            return hotKeys
        }

        return nil
    }

    private static func shouldPreferPersistentStore(
        defaults: UserDefaults,
        preferencesURL: URL?
    ) -> Bool {
        preferencesURL != nil || defaults === UserDefaults.standard
    }

    private static func readHotKeysFromPersistentStore(preferencesURL: URL?) -> [String: Any]? {
        let url = safePreferencesURL(preferencesURL)
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(symbolicHotKeysPlistPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any] else {
            return nil
        }
        return root[symbolicHotKeysKey] as? [String: Any]
    }

    private static func safePreferencesURL(_ preferencesURL: URL?) -> URL? {
        guard let preferencesURL, preferencesURL.isFileURL else {
            return nil
        }

        return preferencesURL.standardizedFileURL
    }

    static func currentDesktopCount(
        snapshot: CGSBridge.ManagedSnapshot? = nil,
        cgsBridge: any CGSBridgeProtocol
    ) -> Int {
        let snapshot = snapshot ?? cgsBridge.managedSnapshot()
        let desktopIDs = Set(
            snapshot.spaces
                .filter { $0.kind == .desktop }
                .map(\.id)
        )
        let detectedCount = snapshot.orderedIDsByDisplay.values
            .map { order in order.filter { desktopIDs.contains($0) }.count }
            .max()
            ?? desktopIDs.count
        return max(1, min(detectedCount, requiredShortcuts.count))
    }

    private static func failureDescription(for requirement: Requirement, hotKeys: [String: Any]) -> String? {
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

    private static func requirement(forDesktopIndex desktopIndex: Int) -> Requirement? {
        requiredShortcuts.first { displayDigit(for: $0.keyCode) == String(desktopIndex) }
    }

    private static func requirements(forDesktopCount desktopCount: Int) -> ArraySlice<Requirement> {
        let count = max(1, min(desktopCount, requiredShortcuts.count))
        return requiredShortcuts.prefix(count)
    }

    private static func shortcutRangeDescription(forDesktopCount desktopCount: Int) -> String {
        let count = max(1, desktopCount)
        return count == 1 ? "Control+1" : "Control+1 through Control+\(count)"
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
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        default: return "?"
        }
    }
}
