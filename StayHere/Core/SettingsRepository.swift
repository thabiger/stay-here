import Foundation

public protocol SettingsRepository: AnyObject {
    var appearanceMode: AppearanceMode { get set }

    var diagnosticsEnabled: Bool { get set }
    var automaticUpdateChecksEnabled: Bool { get set }

    var spaceSwitcherEnabled: Bool { get set }
    var spaceSwitcherShortcutText: String { get set }

    var windowSwitcherEnabled: Bool { get set }
    var windowSwitcherShortcutText: String { get set }
    var windowSwitcherTitleFormat: WindowSwitcherTitleFormat { get set }
    var windowSwitcherShowMinimizedWindows: Bool { get set }
    var windowSwitcherShowHiddenWindows: Bool { get set }
    var hotCornerTopLeftAction: HotCornerAction { get set }
    var hotCornerTopRightAction: HotCornerAction { get set }
    var hotCornerBottomLeftAction: HotCornerAction { get set }
    var hotCornerBottomRightAction: HotCornerAction { get set }

    var hudDisplayDuration: TimeInterval { get set }

    var activationDockClickInterceptionEnabled: Bool { get set }
    var activationSingleWindowAppBundleIDs: [String] { get set }
}
