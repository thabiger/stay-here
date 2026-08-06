import Foundation

/// Shared backing storage for the UserDefaults*Settings types.
/// Subclasses inherit `defaults` and `init(defaults:)`.
public class SettingsBackingStore {
    internal let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

extension UserDefaults {
    /// Presence-checked Bool: explicit stored `false` is honored; only an unset
    /// key falls back to `defaultValue`.
    public subscript(setting key: String, default defaultValue: @autoclosure () -> Bool) -> Bool {
        get {
            if object(forKey: key) != nil { return bool(forKey: key) }
            return defaultValue()
        }
        set { set(newValue, forKey: key) }
    }

    /// String-raw-value enum; invalid/missing stored value falls back to `defaultValue`.
    public subscript<T: RawRepresentable>(setting key: String, default defaultValue: @autoclosure () -> T) -> T
        where T.RawValue == String {
        get {
            guard let raw = string(forKey: key), let value = T(rawValue: raw) else {
                return defaultValue()
            }
            return value
        }
        set { set(newValue.rawValue, forKey: key) }
    }

    /// Trimmed shortcut text: trims on write; whitespace-only stored value reads as
    /// unset (returns `defaultValue`). Non-blank stored value is returned verbatim.
    public subscript(settingTrimmed key: String, default defaultValue: @autoclosure () -> String) -> String {
        get {
            if let stored = string(forKey: key),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return defaultValue()
        }
        set { set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key) }
    }

    /// Clamped TimeInterval with zero-guard: stored <= 0 (or unset) reads as
    /// `defaultValue`; otherwise clamped into `range` on read AND write.
    public subscript(setting key: String, default defaultValue: @autoclosure () -> TimeInterval,
                     clampedTo range: ClosedRange<TimeInterval>) -> TimeInterval {
        get {
            let stored = double(forKey: key)
            guard stored > 0 else { return defaultValue() }
            return min(max(stored, range.lowerBound), range.upperBound)
        }
        set { set(min(max(newValue, range.lowerBound), range.upperBound), forKey: key) }
    }
}
