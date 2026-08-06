import Foundation

public final class UserDefaultsHUDSettings: SettingsBackingStore, HUDSettings {
    private enum Key {
        static let hudDisplayDuration = "hud.display.seconds"
    }

    private enum Defaults {
        static let hudDisplayDuration: TimeInterval = 1.8
        static let hudMinimumDuration: TimeInterval = 0.5
        static let hudMaximumDuration: TimeInterval = 6.0
    }

    public var hudDisplayDuration: TimeInterval {
        get { defaults[setting: Key.hudDisplayDuration, default: Defaults.hudDisplayDuration,
                      clampedTo: Defaults.hudMinimumDuration...Defaults.hudMaximumDuration] }
        set { defaults[setting: Key.hudDisplayDuration, default: Defaults.hudDisplayDuration,
                      clampedTo: Defaults.hudMinimumDuration...Defaults.hudMaximumDuration] = newValue }
    }
}
