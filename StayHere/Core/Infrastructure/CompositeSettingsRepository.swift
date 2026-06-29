import Foundation

public final class CompositeSettingsRepository: SettingsRepository {
    private let _appearance: UserDefaultsAppearanceSettings
    private let _diagnostics: UserDefaultsDiagnosticsSettings
    private let _updates: UserDefaultsUpdateSettings
    private let _spaceSwitcher: UserDefaultsSpaceSwitcherSettings
    private let _windowSwitcher: UserDefaultsWindowSwitcherSettings
    private let _allSpacesWindowSwitcher: UserDefaultsAllSpacesWindowSwitcherSettings
    private let _hotCorner: UserDefaultsHotCornerSettings
    private let _hud: UserDefaultsHUDSettings
    private let _activation: UserDefaultsActivationSettings

    public init(
        appearance: UserDefaultsAppearanceSettings = UserDefaultsAppearanceSettings(),
        diagnostics: UserDefaultsDiagnosticsSettings = UserDefaultsDiagnosticsSettings(),
        updates: UserDefaultsUpdateSettings = UserDefaultsUpdateSettings(),
        spaceSwitcher: UserDefaultsSpaceSwitcherSettings = UserDefaultsSpaceSwitcherSettings(),
        windowSwitcher: UserDefaultsWindowSwitcherSettings = UserDefaultsWindowSwitcherSettings(),
        allSpacesWindowSwitcher: UserDefaultsAllSpacesWindowSwitcherSettings = UserDefaultsAllSpacesWindowSwitcherSettings(),
        hotCorner: UserDefaultsHotCornerSettings = UserDefaultsHotCornerSettings(),
        hud: UserDefaultsHUDSettings = UserDefaultsHUDSettings(),
        activation: UserDefaultsActivationSettings = UserDefaultsActivationSettings()
    ) {
        self._appearance = appearance
        self._diagnostics = diagnostics
        self._updates = updates
        self._spaceSwitcher = spaceSwitcher
        self._windowSwitcher = windowSwitcher
        self._allSpacesWindowSwitcher = allSpacesWindowSwitcher
        self._hotCorner = hotCorner
        self._hud = hud
        self._activation = activation
    }

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(
            appearance: UserDefaultsAppearanceSettings(defaults: defaults),
            diagnostics: UserDefaultsDiagnosticsSettings(defaults: defaults),
            updates: UserDefaultsUpdateSettings(defaults: defaults),
            spaceSwitcher: UserDefaultsSpaceSwitcherSettings(defaults: defaults),
            windowSwitcher: UserDefaultsWindowSwitcherSettings(defaults: defaults),
            allSpacesWindowSwitcher: UserDefaultsAllSpacesWindowSwitcherSettings(defaults: defaults),
            hotCorner: UserDefaultsHotCornerSettings(defaults: defaults),
            hud: UserDefaultsHUDSettings(defaults: defaults),
            activation: UserDefaultsActivationSettings(defaults: defaults)
        )
    }

    // MARK: - AppearanceSettings

    public var appearanceMode: AppearanceMode {
        get { _appearance.appearanceMode }
        set { _appearance.appearanceMode = newValue }
    }

    // MARK: - DiagnosticsSettings

    public var diagnosticsEnabled: Bool {
        get { _diagnostics.diagnosticsEnabled }
        set { _diagnostics.diagnosticsEnabled = newValue }
    }

    // MARK: - UpdateSettings

    public var automaticUpdateChecksEnabled: Bool {
        get { _updates.automaticUpdateChecksEnabled }
        set { _updates.automaticUpdateChecksEnabled = newValue }
    }

    // MARK: - SpaceSwitcherSettings

    public var spaceSwitcherEnabled: Bool {
        get { _spaceSwitcher.spaceSwitcherEnabled }
        set { _spaceSwitcher.spaceSwitcherEnabled = newValue }
    }

    public var spaceSwitcherShortcutText: String {
        get { _spaceSwitcher.spaceSwitcherShortcutText }
        set { _spaceSwitcher.spaceSwitcherShortcutText = newValue }
    }

    // MARK: - WindowSwitcherSettings

    public var windowSwitcherEnabled: Bool {
        get { _windowSwitcher.windowSwitcherEnabled }
        set { _windowSwitcher.windowSwitcherEnabled = newValue }
    }

    public var windowSwitcherShortcutText: String {
        get { _windowSwitcher.windowSwitcherShortcutText }
        set { _windowSwitcher.windowSwitcherShortcutText = newValue }
    }

    public var windowSwitcherTitleFormat: WindowSwitcherTitleFormat {
        get { _windowSwitcher.windowSwitcherTitleFormat }
        set { _windowSwitcher.windowSwitcherTitleFormat = newValue }
    }

    public var windowSwitcherShowMinimizedWindows: Bool {
        get { _windowSwitcher.windowSwitcherShowMinimizedWindows }
        set { _windowSwitcher.windowSwitcherShowMinimizedWindows = newValue }
    }

    public var windowSwitcherShowHiddenWindows: Bool {
        get { _windowSwitcher.windowSwitcherShowHiddenWindows }
        set { _windowSwitcher.windowSwitcherShowHiddenWindows = newValue }
    }

    // MARK: - AllSpacesWindowSwitcherSettings

    public var allSpacesWindowSwitcherEnabled: Bool {
        get { _allSpacesWindowSwitcher.allSpacesWindowSwitcherEnabled }
        set { _allSpacesWindowSwitcher.allSpacesWindowSwitcherEnabled = newValue }
    }

    public var allSpacesWindowSwitcherShortcutText: String {
        get { _allSpacesWindowSwitcher.allSpacesWindowSwitcherShortcutText }
        set { _allSpacesWindowSwitcher.allSpacesWindowSwitcherShortcutText = newValue }
    }

    // MARK: - HotCornerSettings

    public var hotCornerTopLeftAction: HotCornerAction {
        get { _hotCorner.hotCornerTopLeftAction }
        set { _hotCorner.hotCornerTopLeftAction = newValue }
    }

    public var hotCornerTopRightAction: HotCornerAction {
        get { _hotCorner.hotCornerTopRightAction }
        set { _hotCorner.hotCornerTopRightAction = newValue }
    }

    public var hotCornerBottomLeftAction: HotCornerAction {
        get { _hotCorner.hotCornerBottomLeftAction }
        set { _hotCorner.hotCornerBottomLeftAction = newValue }
    }

    public var hotCornerBottomRightAction: HotCornerAction {
        get { _hotCorner.hotCornerBottomRightAction }
        set { _hotCorner.hotCornerBottomRightAction = newValue }
    }

    // MARK: - HUDSettings

    public var hudDisplayDuration: TimeInterval {
        get { _hud.hudDisplayDuration }
        set { _hud.hudDisplayDuration = newValue }
    }

    // MARK: - ActivationSettings

    public var activationDockClickInterceptionEnabled: Bool {
        get { _activation.activationDockClickInterceptionEnabled }
        set { _activation.activationDockClickInterceptionEnabled = newValue }
    }

    public var activationSingleWindowAppBundleIDs: [String] {
        get { _activation.activationSingleWindowAppBundleIDs }
        set { _activation.activationSingleWindowAppBundleIDs = newValue }
    }
}
