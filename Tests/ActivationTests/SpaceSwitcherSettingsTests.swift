import XCTest
import Core

final class SpaceSwitcherSettingsTests: XCTestCase {
    func testDefaultShortcutIsCommandTab() {
        let suiteName = "SpaceSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SpaceSwitcherSettings(defaults: defaults)

        XCTAssertEqual(settings.shortcutText, "command+tab")
        XCTAssertEqual(settings.shortcut.displayString, "command+tab")
        XCTAssertTrue(settings.isEnabled)
    }

    func testPersistsEnabledFlag() {
        let suiteName = "SpaceSwitcherSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = SpaceSwitcherSettings(defaults: defaults)
        settings.isEnabled = false

        XCTAssertFalse(settings.isEnabled)

        let reread = SpaceSwitcherSettings(defaults: defaults)
        XCTAssertFalse(reread.isEnabled)
    }

    func testParsesCustomShortcutText() {
        XCTAssertEqual(
            SpaceSwitcherSettings.parseShortcut("control+space"),
            SpaceSwitcherShortcut(keyCode: 49, modifiers: [.maskControl])
        )
        XCTAssertEqual(
            SpaceSwitcherSettings.parseShortcut("command+shift+tab"),
            SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand, .maskShift])
        )
        XCTAssertEqual(
            SpaceSwitcherSettings.parseShortcut("command+`"),
            SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
        )
    }

    func testRejectsInvalidShortcutText() {
        XCTAssertNil(SpaceSwitcherSettings.parseShortcut("option+not-a-key"))
        XCTAssertNil(SpaceSwitcherSettings.parseShortcut("justwords"))
    }
}
