import XCTest
import Core

final class WindowSwitcherTitleFormatTests: XCTestCase {
    func testAppNameOnlyReturnsAppName() {
        XCTAssertEqual(
            WindowSwitcherTitleFormat.displayTitle(
                appName: "Notes",
                windowTitle: "Untitled",
                format: .appNameOnly
            ),
            "Notes"
        )
    }

    func testAppNameAndWindowTitleReturnsBoth() {
        XCTAssertEqual(
            WindowSwitcherTitleFormat.displayTitle(
                appName: "Notes",
                windowTitle: "Untitled",
                format: .appNameAndWindowTitle
            ),
            "Notes: Untitled"
        )
    }

    func testFallsBackToAppNameWhenTitleIsNil() {
        XCTAssertEqual(
            WindowSwitcherTitleFormat.displayTitle(
                appName: "Notes",
                windowTitle: nil,
                format: .appNameAndWindowTitle
            ),
            "Notes"
        )
    }

    func testFallsBackToAppNameWhenTitleIsEmpty() {
        XCTAssertEqual(
            WindowSwitcherTitleFormat.displayTitle(
                appName: "Notes",
                windowTitle: "   ",
                format: .appNameAndWindowTitle
            ),
            "Notes"
        )
    }

    func testFallsBackToAppNameWhenTitleMatchesAppName() {
        XCTAssertEqual(
            WindowSwitcherTitleFormat.displayTitle(
                appName: "Notes",
                windowTitle: "Notes",
                format: .appNameAndWindowTitle
            ),
            "Notes"
        )
    }
}
