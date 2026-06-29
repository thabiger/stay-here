import Foundation

public protocol AppearanceSettings: AnyObject {
    var appearanceMode: AppearanceMode { get set }
}

public protocol DiagnosticsSettings: AnyObject {
    var diagnosticsEnabled: Bool { get set }
}

public protocol UpdateSettings: AnyObject {
    var automaticUpdateChecksEnabled: Bool { get set }
}

public protocol SpaceSwitcherSettings: AnyObject {
    var spaceSwitcherEnabled: Bool { get set }
    var spaceSwitcherShortcutText: String { get set }
}

public protocol WindowSwitcherSettings: AnyObject {
    var windowSwitcherEnabled: Bool { get set }
    var windowSwitcherShortcutText: String { get set }
    var windowSwitcherTitleFormat: WindowSwitcherTitleFormat { get set }
    var windowSwitcherShowMinimizedWindows: Bool { get set }
    var windowSwitcherShowHiddenWindows: Bool { get set }
}

public protocol AllSpacesWindowSwitcherSettings: AnyObject {
    var allSpacesWindowSwitcherEnabled: Bool { get set }
    var allSpacesWindowSwitcherShortcutText: String { get set }
}

public protocol HotCornerSettings: AnyObject {
    var hotCornerTopLeftAction: HotCornerAction { get set }
    var hotCornerTopRightAction: HotCornerAction { get set }
    var hotCornerBottomLeftAction: HotCornerAction { get set }
    var hotCornerBottomRightAction: HotCornerAction { get set }
}

public protocol HUDSettings: AnyObject {
    var hudDisplayDuration: TimeInterval { get set }
}

public protocol ActivationSettings: AnyObject {
    var activationDockClickInterceptionEnabled: Bool { get set }
    var activationSingleWindowAppBundleIDs: [String] { get set }
}

public protocol SettingsRepository: AppearanceSettings, DiagnosticsSettings, UpdateSettings, SpaceSwitcherSettings, WindowSwitcherSettings, AllSpacesWindowSwitcherSettings, HotCornerSettings, HUDSettings, ActivationSettings {}
