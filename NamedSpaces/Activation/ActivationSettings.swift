import Foundation

public final class ActivationSettings {
    public static let shared = ActivationSettings()

    private let defaults = UserDefaults.standard
    private let key = "activation.mode"

    public var mode: ActivationMode {
        get {
            guard let raw = defaults.string(forKey: key), let mode = ActivationMode(rawValue: raw) else {
                return .replaceDockClicks
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
