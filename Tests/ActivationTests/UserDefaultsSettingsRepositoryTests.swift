import XCTest
import Core

final class UserDefaultsSettingsRepositoryTests: XCTestCase {
    func testAppearanceModeDefaultsToSystem() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.appearanceMode, .system)
    }

    func testAppearanceModeIgnoresInvalidStoredValue() {
        let defaults = makeDefaults()
        defaults.set("banana", forKey: "appearance.mode")
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.appearanceMode, .system)
    }

    func testAppearanceModePersistsAcrossInstances() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.appearanceMode = .dark

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertEqual(reader.appearanceMode, .dark)
    }

    func testSpaceSwitcherDefaultsAreCommandTab() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.spaceSwitcherShortcutText, "command+tab")
        XCTAssertTrue(settings.spaceSwitcherEnabled)
    }

    func testSpaceSwitcherShortcutPersists() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.spaceSwitcherShortcutText = "control+space"
        writer.spaceSwitcherEnabled = false

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertEqual(reader.spaceSwitcherShortcutText, "control+space")
        XCTAssertFalse(reader.spaceSwitcherEnabled)
    }

    func testWindowSwitcherDefaultsAreCommandBacktick() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.windowSwitcherShortcutText, "command+`")
        XCTAssertTrue(settings.windowSwitcherEnabled)
        XCTAssertEqual(settings.windowSwitcherTitleFormat, .appNameOnly)
        XCTAssertFalse(settings.windowSwitcherShowMinimizedWindows)
        XCTAssertFalse(settings.windowSwitcherShowHiddenWindows)
    }

    func testWindowSwitcherShortcutPersists() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.windowSwitcherShortcutText = "control+space"
        writer.windowSwitcherEnabled = false

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertEqual(reader.windowSwitcherShortcutText, "control+space")
        XCTAssertFalse(reader.windowSwitcherEnabled)
    }

    func testWindowSwitcherTitleFormatPersists() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.windowSwitcherTitleFormat = .appNameAndWindowTitle

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertEqual(reader.windowSwitcherTitleFormat, .appNameAndWindowTitle)
    }

    func testWindowSwitcherVisibilityFlagsPersist() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.windowSwitcherShowMinimizedWindows = true
        writer.windowSwitcherShowHiddenWindows = true

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertTrue(reader.windowSwitcherShowMinimizedWindows)
        XCTAssertTrue(reader.windowSwitcherShowHiddenWindows)
    }

    func testHUDDisplayDurationDefaultsTo180() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.hudDisplayDuration, 1.8, accuracy: 0.0001)
    }

    func testHUDDisplayDurationClampsToBounds() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        settings.hudDisplayDuration = 0.1
        XCTAssertEqual(settings.hudDisplayDuration, 0.5, accuracy: 0.0001)

        settings.hudDisplayDuration = 9.0
        XCTAssertEqual(settings.hudDisplayDuration, 6.0, accuracy: 0.0001)
    }

    func testHUDDisplayDurationFallsBackToDefaultWhenZeroOrNegative() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "hud.display.seconds")
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertEqual(settings.hudDisplayDuration, 1.8, accuracy: 0.0001)
    }

    func testActivationDefaultsAreEnabledWithDefaultBundleIDs() {
        let defaults = makeDefaults()
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertTrue(settings.activationDockClickInterceptionEnabled)
        XCTAssertEqual(settings.activationSingleWindowAppBundleIDs, ["com.apple.Notes", "com.openai.codex"])
    }

    func testActivationDockClickInterceptionHonoursLegacyDisabled() {
        let defaults = makeDefaults()
        defaults.set("disabled", forKey: "activation.mode")
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertFalse(settings.activationDockClickInterceptionEnabled)
    }

    func testActivationDockClickInterceptionPrefersExplicitSettingOverLegacy() {
        let defaults = makeDefaults()
        defaults.set("disabled", forKey: "activation.mode")
        defaults.set(true, forKey: "activation.enabled")
        let settings = UserDefaultsSettingsRepository(defaults: defaults)

        XCTAssertTrue(settings.activationDockClickInterceptionEnabled)
    }

    func testActivationSingleWindowAppBundleIDsPersist() {
        let defaults = makeDefaults()
        let writer = UserDefaultsSettingsRepository(defaults: defaults)
        writer.activationSingleWindowAppBundleIDs = ["com.example.A", "com.example.B"]

        let reader = UserDefaultsSettingsRepository(defaults: defaults)
        XCTAssertEqual(reader.activationSingleWindowAppBundleIDs, ["com.example.A", "com.example.B"])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UserDefaultsSettingsRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
