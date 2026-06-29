import Foundation

public final class UserDefaultsActivationSettings: ActivationSettings {
    private enum Key {
        static let activationEnabled = "activation.enabled"
        static let activationSingleWindowAppBundleIDs = "activation.singleWindowAppBundleIDs"
        static let activationLegacyMode = "activation.mode"
    }

    private enum Defaults {
        static let activationDockClickInterceptionEnabled: Bool = true
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var activationDockClickInterceptionEnabled: Bool {
        get {
            if defaults.object(forKey: Key.activationEnabled) != nil {
                return defaults.bool(forKey: Key.activationEnabled)
            }
            guard let legacyRaw = defaults.string(forKey: Key.activationLegacyMode) else {
                return Defaults.activationDockClickInterceptionEnabled
            }
            return legacyRaw != "disabled"
        }
        set {
            defaults.set(newValue, forKey: Key.activationEnabled)
        }
    }

    public var activationSingleWindowAppBundleIDs: [String] {
        get {
            if let stored = defaults.string(forKey: Key.activationSingleWindowAppBundleIDs) {
                let parsed = SingleWindowAppBundleIDList.parse(stored)
                if !parsed.isEmpty || defaults.object(forKey: Key.activationSingleWindowAppBundleIDs) != nil {
                    return parsed
                }
            }
            return SingleWindowAppBundleIDList.defaultBundleIDs
        }
        set {
            defaults.set(SingleWindowAppBundleIDList.serialize(newValue), forKey: Key.activationSingleWindowAppBundleIDs)
        }
    }
}
