import Foundation

public final class UserDefaultsUpdateSettings: SettingsBackingStore, UpdateSettings {
    private enum Key {
        static let automaticUpdateChecksEnabled = "updates.automatic.enabled"
    }

    private enum Defaults {
        static let automaticUpdateChecksEnabled: Bool = true
    }

    public var automaticUpdateChecksEnabled: Bool {
        get { defaults[setting: Key.automaticUpdateChecksEnabled, default: Defaults.automaticUpdateChecksEnabled] }
        set { defaults[setting: Key.automaticUpdateChecksEnabled, default: Defaults.automaticUpdateChecksEnabled] = newValue }
    }
}
