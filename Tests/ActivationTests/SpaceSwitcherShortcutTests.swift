import XCTest
import Core

final class SpaceSwitcherShortcutTests: XCTestCase {
    func testParsesControlSpace() {
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse("control+space"),
            SpaceSwitcherShortcut(keyCode: 49, modifiers: [.maskControl])
        )
    }

    func testParsesCommandShiftTab() {
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse("command+shift+tab"),
            SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskCommand, .maskShift])
        )
    }

    func testParsesCommandBacktick() {
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse("command+`"),
            SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
        )
    }

    func testRejectsInvalidKeyName() {
        XCTAssertNil(SpaceSwitcherShortcut.parse("option+not-a-key"))
    }

    func testRejectsTextWithoutModifiers() {
        XCTAssertNil(SpaceSwitcherShortcut.parse("justwords"))
    }

    func testRejectsEmptyText() {
        XCTAssertNil(SpaceSwitcherShortcut.parse(""))
    }

    func testDisplayStringRendersInOrder() {
        let shortcut = SpaceSwitcherShortcut(keyCode: 48, modifiers: [.maskControl, .maskShift, .maskCommand])
        XCTAssertEqual(shortcut.displayString, "control+shift+command+tab")
    }

    func testAcceptsAliasTokens() {
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse("cmd+alt+a"),
            SpaceSwitcherShortcut(keyCode: 0, modifiers: [.maskCommand, .maskAlternate])
        )
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse("ctrl+option+q"),
            SpaceSwitcherShortcut(keyCode: 12, modifiers: [.maskControl, .maskAlternate])
        )
    }

    func testIgnoresWhitespace() {
        XCTAssertEqual(
            SpaceSwitcherShortcut.parse(" control + space "),
            SpaceSwitcherShortcut(keyCode: 49, modifiers: [.maskControl])
        )
    }
}
