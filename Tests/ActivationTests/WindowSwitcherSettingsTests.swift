import XCTest
import Core

final class WindowSwitcherSettingsTests: XCTestCase {
    func testDefaultShortcutIsCommandBacktick() {
        let suiteName = "WindowSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = WindowSwitcherSettings(defaults: defaults)

        XCTAssertEqual(settings.shortcutText, "command+`")
        XCTAssertEqual(settings.shortcut.displayString, "command+backtick")
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.titleFormat, .appNameOnly)
        XCTAssertFalse(settings.showMinimizedWindows)
        XCTAssertFalse(settings.showHiddenWindows)
    }

    func testPersistsEnabledFlag() {
        let suiteName = "WindowSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = WindowSwitcherSettings(defaults: defaults)
        settings.isEnabled = false

        XCTAssertFalse(settings.isEnabled)

        let reread = WindowSwitcherSettings(defaults: defaults)
        XCTAssertFalse(reread.isEnabled)
    }

    func testParsesCustomShortcutText() {
        XCTAssertEqual(
            WindowSwitcherSettings.parseShortcut("control+space"),
            SpaceSwitcherShortcut(keyCode: 49, modifiers: [.maskControl])
        )
        XCTAssertEqual(
            WindowSwitcherSettings.parseShortcut("command+shift+tab"),
            SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand, .maskShift])
        )
    }

    func testRejectsInvalidShortcutText() {
        XCTAssertNil(WindowSwitcherSettings.parseShortcut("command+not-a-key"))
        XCTAssertNil(WindowSwitcherSettings.parseShortcut("justwords"))
    }

    func testPersistsVisibilityFlags() {
        let suiteName = "WindowSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = WindowSwitcherSettings(defaults: defaults)
        settings.showMinimizedWindows = true
        settings.showHiddenWindows = true

        XCTAssertTrue(settings.showMinimizedWindows)
        XCTAssertTrue(settings.showHiddenWindows)

        let reread = WindowSwitcherSettings(defaults: defaults)
        XCTAssertTrue(reread.showMinimizedWindows)
        XCTAssertTrue(reread.showHiddenWindows)
    }

    func testPersistsTitleFormat() {
        let suiteName = "WindowSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = WindowSwitcherSettings(defaults: defaults)
        settings.titleFormat = .appNameAndWindowTitle

        XCTAssertEqual(settings.titleFormat, .appNameAndWindowTitle)

        let reread = WindowSwitcherSettings(defaults: defaults)
        XCTAssertEqual(reread.titleFormat, .appNameAndWindowTitle)
    }

    func testFormatsWindowTitleBasedOnSetting() {
        XCTAssertEqual(
            WindowSwitcherSettings.displayTitle(
                appName: "Notes",
                windowTitle: "Untitled",
                format: .appNameOnly
            ),
            "Notes"
        )
        XCTAssertEqual(
            WindowSwitcherSettings.displayTitle(
                appName: "Notes",
                windowTitle: "Untitled",
                format: .appNameAndWindowTitle
            ),
            "Notes: Untitled"
        )
        XCTAssertEqual(
            WindowSwitcherSettings.displayTitle(
                appName: "Notes",
                windowTitle: nil,
                format: .appNameAndWindowTitle
            ),
            "Notes"
        )
    }
}
