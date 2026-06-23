import Foundation

public final class UserDefaultsDiagnosticsSettings: DiagnosticsSettings {
    private enum Key {
        static let diagnosticsEnabled = "diagnostics.enabled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var diagnosticsEnabled: Bool {
        get {
            if defaults.object(forKey: Key.diagnosticsEnabled) != nil {
                return defaults.bool(forKey: Key.diagnosticsEnabled)
            }
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        set {
            defaults.set(newValue, forKey: Key.diagnosticsEnabled)
        }
    }
}
