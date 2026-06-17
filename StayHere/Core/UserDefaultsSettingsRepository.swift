import Foundation

public final class UserDefaultsSettingsRepository: SettingsRepository {
    private enum Key {
        static let appearanceMode = "appearance.mode"

        static let diagnosticsEnabled = "diagnostics.enabled"
        static let automaticUpdateChecksEnabled = "updates.automatic.enabled"

        static let spaceSwitcherEnabled = "spaceSwitcher.enabled"
        static let spaceSwitcherShortcut = "spaceSwitcher.shortcut"

        static let windowSwitcherEnabled = "windowSwitcher.enabled"
        static let windowSwitcherShortcut = "windowSwitcher.shortcut"
        static let windowSwitcherTitleFormat = "windowSwitcher.titleFormat"
        static let windowSwitcherShowMinimizedWindows = "windowSwitcher.showMinimizedWindows"
        static let windowSwitcherShowHiddenWindows = "windowSwitcher.showHiddenWindows"
        static let hotCornerTopLeftAction = "hotCorner.topLeft.action"
        static let hotCornerTopRightAction = "hotCorner.topRight.action"
        static let hotCornerBottomLeftAction = "hotCorner.bottomLeft.action"
        static let hotCornerBottomRightAction = "hotCorner.bottomRight.action"

        static let hudDisplayDuration = "hud.display.seconds"

        static let activationEnabled = "activation.enabled"
        static let activationSingleWindowAppBundleIDs = "activation.singleWindowAppBundleIDs"
        static let activationLegacyMode = "activation.mode"
    }

    private enum Defaults {
        static let appearanceMode: AppearanceMode = .system
        static let automaticUpdateChecksEnabled: Bool = true
        static let spaceSwitcherShortcut = "command+tab"
        static let spaceSwitcherEnabled: Bool = true
        static let windowSwitcherShortcut = "command+`"
        static let windowSwitcherEnabled: Bool = true
        static let windowSwitcherTitleFormat: WindowSwitcherTitleFormat = .appNameOnly
        static let windowSwitcherShowMinimizedWindows: Bool = false
        static let windowSwitcherShowHiddenWindows: Bool = false
        static let hotCornerAction: HotCornerAction = .none
        static let hudDisplayDuration: TimeInterval = 1.8
        static let activationDockClickInterceptionEnabled: Bool = true

        static let hudMinimumDuration: TimeInterval = 0.5
        static let hudMaximumDuration: TimeInterval = 6.0
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var appearanceMode: AppearanceMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.appearanceMode),
                  let mode = AppearanceMode(rawValue: rawValue) else {
                return Defaults.appearanceMode
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearanceMode)
        }
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

    public var automaticUpdateChecksEnabled: Bool {
        get {
            if defaults.object(forKey: Key.automaticUpdateChecksEnabled) != nil {
                return defaults.bool(forKey: Key.automaticUpdateChecksEnabled)
            }
            return Defaults.automaticUpdateChecksEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.automaticUpdateChecksEnabled)
        }
    }

    public var spaceSwitcherEnabled: Bool {
        get {
            if defaults.object(forKey: Key.spaceSwitcherEnabled) != nil {
                return defaults.bool(forKey: Key.spaceSwitcherEnabled)
            }
            return Defaults.spaceSwitcherEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.spaceSwitcherEnabled)
        }
    }

    public var spaceSwitcherShortcutText: String {
        get {
            if let stored = defaults.string(forKey: Key.spaceSwitcherShortcut),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return Defaults.spaceSwitcherShortcut
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.spaceSwitcherShortcut)
        }
    }

    public var windowSwitcherEnabled: Bool {
        get {
            if defaults.object(forKey: Key.windowSwitcherEnabled) != nil {
                return defaults.bool(forKey: Key.windowSwitcherEnabled)
            }
            return Defaults.windowSwitcherEnabled
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherEnabled)
        }
    }

    public var windowSwitcherShortcutText: String {
        get {
            if let stored = defaults.string(forKey: Key.windowSwitcherShortcut),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored
            }
            return Defaults.windowSwitcherShortcut
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.windowSwitcherShortcut)
        }
    }

    public var windowSwitcherTitleFormat: WindowSwitcherTitleFormat {
        get {
            if let stored = defaults.string(forKey: Key.windowSwitcherTitleFormat),
               let format = WindowSwitcherTitleFormat(rawValue: stored) {
                return format
            }
            return Defaults.windowSwitcherTitleFormat
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.windowSwitcherTitleFormat)
        }
    }

    public var windowSwitcherShowMinimizedWindows: Bool {
        get {
            defaults.object(forKey: Key.windowSwitcherShowMinimizedWindows) != nil
                ? defaults.bool(forKey: Key.windowSwitcherShowMinimizedWindows)
                : Defaults.windowSwitcherShowMinimizedWindows
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherShowMinimizedWindows)
        }
    }

    public var windowSwitcherShowHiddenWindows: Bool {
        get {
            defaults.object(forKey: Key.windowSwitcherShowHiddenWindows) != nil
                ? defaults.bool(forKey: Key.windowSwitcherShowHiddenWindows)
                : Defaults.windowSwitcherShowHiddenWindows
        }
        set {
            defaults.set(newValue, forKey: Key.windowSwitcherShowHiddenWindows)
        }
    }

    public var hotCornerTopLeftAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerTopLeftAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerTopLeftAction) }
    }

    public var hotCornerTopRightAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerTopRightAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerTopRightAction) }
    }

    public var hotCornerBottomLeftAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerBottomLeftAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerBottomLeftAction) }
    }

    public var hotCornerBottomRightAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerBottomRightAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerBottomRightAction) }
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

    public var activationDockClickInterceptionEnabled: Bool {
        get {
            if defaults.object(forKey: Key.activationEnabled) != nil {
                return defaults.bool(forKey: Key.activationEnabled)
            }
            guard let legacyRaw = defaults.string(forKey: Key.activationLegacyMode) else {
                return Defaults.activationDockClickInterceptionEnabled
            }
            return legacyRaw != "disabled"
        }
        set {
            defaults.set(newValue, forKey: Key.activationEnabled)
        }
    }

    public var activationSingleWindowAppBundleIDs: [String] {
        get {
            if let stored = defaults.string(forKey: Key.activationSingleWindowAppBundleIDs) {
                let parsed = SingleWindowAppBundleIDList.parse(stored)
                if !parsed.isEmpty || defaults.object(forKey: Key.activationSingleWindowAppBundleIDs) != nil {
                    return parsed
                }
            }
            return SingleWindowAppBundleIDList.defaultBundleIDs
        }
        set {
            defaults.set(SingleWindowAppBundleIDList.serialize(newValue), forKey: Key.activationSingleWindowAppBundleIDs)
        }
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, Defaults.hudMinimumDuration), Defaults.hudMaximumDuration)
    }

    private func hotCornerAction(forKey key: String) -> HotCornerAction {
        if let stored = defaults.string(forKey: key),
           let action = HotCornerAction(rawValue: stored) {
            return action
        }
        return Defaults.hotCornerAction
    }
}
