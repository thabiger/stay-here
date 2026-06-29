import Foundation

public final class UserDefaultsAppearanceSettings: AppearanceSettings {
    private enum Key {
        static let appearanceMode = "appearance.mode"
    }

    private enum Defaults {
        static let appearanceMode: AppearanceMode = .system
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var appearanceMode: AppearanceMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.appearanceMode),
                  let mode = AppearanceMode(rawValue: rawValue) else {
                return Defaults.appearanceMode
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearanceMode)
        }
    }
}
