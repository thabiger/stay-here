import Foundation

public final class HUDSettings {
    public static let shared = HUDSettings()

    private let defaults = UserDefaults.standard
    private let key = "hud.display.seconds"

    private let minimumDuration: TimeInterval = 0.5
    private let maximumDuration: TimeInterval = 6.0
    private let defaultDuration: TimeInterval = 1.8

    public var displayDuration: TimeInterval {
        get {
            let stored = defaults.double(forKey: key)
            guard stored > 0 else { return defaultDuration }
            return clamp(stored)
        }
        set {
            defaults.set(clamp(newValue), forKey: key)
        }
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, minimumDuration), maximumDuration)
    }
}
