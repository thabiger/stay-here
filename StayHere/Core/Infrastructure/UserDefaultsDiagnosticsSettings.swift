import Foundation

public final class UserDefaultsDiagnosticsSettings: SettingsBackingStore, DiagnosticsSettings {
    private enum Key {
        static let diagnosticsEnabled = "diagnostics.enabled"
    }

    private enum Defaults {
        static var diagnosticsEnabled: Bool {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }

    public var diagnosticsEnabled: Bool {
        get { defaults[setting: Key.diagnosticsEnabled, default: Defaults.diagnosticsEnabled] }
        set { defaults[setting: Key.diagnosticsEnabled, default: Defaults.diagnosticsEnabled] = newValue }
    }
}
