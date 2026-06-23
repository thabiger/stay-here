import Foundation

public final class UserDefaultsHUDSettings: HUDSettings {
    private enum Key {
        static let hudDisplayDuration = "hud.display.seconds"
    }

    private enum Defaults {
        static let hudDisplayDuration: TimeInterval = 1.8
        static let hudMinimumDuration: TimeInterval = 0.5
        static let hudMaximumDuration: TimeInterval = 6.0
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hudDisplayDuration: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.hudDisplayDuration)
            guard stored > 0 else { return Defaults.hudDisplayDuration }
            return clamp(stored)
        }
        set {
            defaults.set(clamp(newValue), forKey: Key.hudDisplayDuration)
        }
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, Defaults.hudMinimumDuration), Defaults.hudMaximumDuration)
    }
}
