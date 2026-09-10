import Foundation

public final class UserDefaultsAppearanceSettings: SettingsBackingStore, AppearanceSettings {
    private enum Key {
        static let appearanceMode = "appearance.mode"
    }

    private enum Defaults {
        static let appearanceMode: AppearanceMode = .system
    }

    public var appearanceMode: AppearanceMode {
        get { defaults[setting: Key.appearanceMode, default: Defaults.appearanceMode] }
        set { defaults[setting: Key.appearanceMode, default: Defaults.appearanceMode] = newValue }
    }
}
