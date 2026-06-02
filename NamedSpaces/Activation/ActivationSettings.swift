import Foundation

public final class ActivationSettings {
    public static let shared = ActivationSettings()

    private let defaults: UserDefaults
    private let enabledKey = "activation.enabled"
    private let singleWindowAppBundleIDsKey = "activation.singleWindowAppBundleIDs"
    private let legacyModeKey = "activation.mode"
    private let defaultSingleWindowAppBundleIDs = [
        "com.apple.Notes",
        "com.openai.codex"
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var dockClickInterceptionEnabled: Bool {
        get {
            if defaults.object(forKey: enabledKey) != nil {
                return defaults.bool(forKey: enabledKey)
            }

            guard let legacyRaw = defaults.string(forKey: legacyModeKey) else {
                return true
            }

            return legacyRaw != "disabled"
        }
        set {
            defaults.set(newValue, forKey: enabledKey)
        }
    }

    public var singleWindowAppBundleIDs: [String] {
        get {
            if let stored = defaults.string(forKey: singleWindowAppBundleIDsKey) {
                let parsed = Self.parseSingleWindowAppBundleIDs(from: stored)
                if !parsed.isEmpty || defaults.object(forKey: singleWindowAppBundleIDsKey) != nil {
                    return parsed
                }
            }

            return defaultSingleWindowAppBundleIDs
        }
        set {
            defaults.set(Self.serializeSingleWindowAppBundleIDs(newValue), forKey: singleWindowAppBundleIDsKey)
        }
    }

    public static func parseSingleWindowAppBundleIDs(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    public static func serializeSingleWindowAppBundleIDs(_ bundleIDs: [String]) -> String {
        var seen = Set<String>()
        return bundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }
}
