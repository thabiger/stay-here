import Foundation

public final class UserDefaultsUpdateSettings: UpdateSettings {
    private enum Key {
        static let automaticUpdateChecksEnabled = "updates.automatic.enabled"
    }

    private enum Defaults {
        static let automaticUpdateChecksEnabled: Bool = true
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var automaticUpdateChecksEnabled: Bool {
        get {
            if defaults.object(forKey: Key.automaticUpdateChecksEnabled) != nil {
                return defaults.bool(forKey: Key.automaticUpdateChecksEnabled)
            }
            return Defaults.automaticUpdateChecksEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.automaticUpdateChecksEnabled)
        }
    }
}
