import Foundation

public final class DiagnosticsSettings {
    public static let shared = DiagnosticsSettings()

    private let defaults: UserDefaults
    private let enabledKey = "diagnostics.enabled"
    private let defaultEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        self.defaultEnabled = true
        #else
        self.defaultEnabled = false
        #endif
    }

    public var isEnabled: Bool {
        get {
            if defaults.object(forKey: enabledKey) != nil {
                return defaults.bool(forKey: enabledKey)
            }

            return defaultEnabled
        }
        set {
            defaults.set(newValue, forKey: enabledKey)
        }
    }
}
