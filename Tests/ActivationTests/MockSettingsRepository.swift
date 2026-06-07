import Foundation
import Core

final class MockSettingsRepository: SettingsRepository {
    var appearanceModeStorage: AppearanceMode = .system
    var appearanceMode: AppearanceMode {
        get { appearanceModeStorage }
        set { appearanceModeStorage = newValue }
    }

    var diagnosticsEnabledStorage: Bool = false
    var diagnosticsEnabled: Bool {
        get { diagnosticsEnabledStorage }
        set { diagnosticsEnabledStorage = newValue }
    }

    var spaceSwitcherEnabledStorage: Bool = true
    var spaceSwitcherEnabled: Bool {
        get { spaceSwitcherEnabledStorage }
        set { spaceSwitcherEnabledStorage = newValue }
    }

    var spaceSwitcherShortcutTextStorage: String = "command+tab"
    var spaceSwitcherShortcutText: String {
        get { spaceSwitcherShortcutTextStorage }
        set { spaceSwitcherShortcutTextStorage = newValue }
    }

    var windowSwitcherEnabledStorage: Bool = true
    var windowSwitcherEnabled: Bool {
        get { windowSwitcherEnabledStorage }
        set { windowSwitcherEnabledStorage = newValue }
    }

    var windowSwitcherShortcutTextStorage: String = "command+`"
    var windowSwitcherShortcutText: String {
        get { windowSwitcherShortcutTextStorage }
        set { windowSwitcherShortcutTextStorage = newValue }
    }

    var windowSwitcherTitleFormatStorage: WindowSwitcherTitleFormat = .appNameOnly
    var windowSwitcherTitleFormat: WindowSwitcherTitleFormat {
        get { windowSwitcherTitleFormatStorage }
        set { windowSwitcherTitleFormatStorage = newValue }
    }

    var windowSwitcherShowMinimizedWindowsStorage: Bool = false
    var windowSwitcherShowMinimizedWindows: Bool {
        get { windowSwitcherShowMinimizedWindowsStorage }
        set { windowSwitcherShowMinimizedWindowsStorage = newValue }
    }

    var windowSwitcherShowHiddenWindowsStorage: Bool = false
    var windowSwitcherShowHiddenWindows: Bool {
        get { windowSwitcherShowHiddenWindowsStorage }
        set { windowSwitcherShowHiddenWindowsStorage = newValue }
    }

    var hudDisplayDurationStorage: TimeInterval = 1.8
    var hudDisplayDuration: TimeInterval {
        get { hudDisplayDurationStorage }
        set { hudDisplayDurationStorage = newValue }
    }

    var activationDockClickInterceptionEnabledStorage: Bool = true
    var activationDockClickInterceptionEnabled: Bool {
        get { activationDockClickInterceptionEnabledStorage }
        set { activationDockClickInterceptionEnabledStorage = newValue }
    }

    var activationSingleWindowAppBundleIDsStorage: [String] = SingleWindowAppBundleIDList.defaultBundleIDs
    var activationSingleWindowAppBundleIDs: [String] {
        get { activationSingleWindowAppBundleIDsStorage }
        set { activationSingleWindowAppBundleIDsStorage = newValue }
    }
}
