import XCTest
@testable import StayHereApp

final class SwitcherCommandTests: XCTestCase {
    func testParsesWindowSwitcherHostStyleURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://window-switcher/open")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .window, action: .open))
    }

    func testParsesSpaceSwitcherNestedOpenURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://switcher/space/open")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .space, action: .open))
    }

    func testParsesGenericSwitcherCloseURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://switcher/close")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .any, action: .close))
    }

    func testParsesGenericSwitcherNextURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://switcher/next")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .any, action: .next))
    }

    func testParsesGenericSwitcherCommitURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://switcher/commit")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .any, action: .commit))
    }

    func testParsesGenericSwitcherSelectURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://switcher/select/3")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .any, action: .select, index: 3))
    }

    func testParsesQueryStyleURL() {
        let command = SwitcherCommand(url: URL(string: "stayhere://command?action=open&target=window")!)

        XCTAssertEqual(command, SwitcherCommand(kind: .window, action: .open))
    }

    func testRejectsDedicatedWindowCloseURL() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://window-switcher/close")!))
    }

    func testRejectsDedicatedSpaceCloseURL() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://space-switcher/close")!))
    }

    func testRejectsDedicatedWindowNextURL() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://window-switcher/next")!))
    }

    func testRejectsDedicatedSpacePreviousURL() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://space-switcher/previous")!))
    }

    func testRejectsDedicatedWindowCommitURL() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://window-switcher/commit")!))
    }

    func testRejectsSelectWithoutIndex() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://switcher/select")!))
    }

    func testRejectsSelectWithInvalidIndex() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "stayhere://switcher/select/0")!))
    }

    func testRejectsUnknownScheme() {
        XCTAssertNil(SwitcherCommand(url: URL(string: "https://window-switcher/open")!))
    }
}
