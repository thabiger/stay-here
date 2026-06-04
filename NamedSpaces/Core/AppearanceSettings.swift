import Foundation

public enum AppearanceMode: String, CaseIterable, Equatable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

public final class AppearanceSettings {
    public static let shared = AppearanceSettings()

    private let defaults: UserDefaults
    private let key = "appearance.mode"
    private let defaultMode: AppearanceMode = .system

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: AppearanceMode {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let mode = AppearanceMode(rawValue: rawValue) else {
                return defaultMode
            }

            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}
