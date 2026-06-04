import XCTest
import Core

final class WindowSwitcherSettingsTests: XCTestCase {
    func testDefaultShortcutIsCommandTab() {
        let suiteName = "WindowSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = WindowSwitcherSettings(defaults: defaults)

        XCTAssertEqual(settings.shortcutText, "command+tab")
        XCTAssertEqual(settings.shortcut.displayString, "command+tab")
        XCTAssertFalse(settings.showMinimizedWindows)
        XCTAssertFalse(settings.showHiddenWindows)
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
}
