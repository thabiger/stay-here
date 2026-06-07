import XCTest
import Core
@testable import StayHereApp

final class SpaceSwitchPresentationHelperTests: XCTestCase {
    func testWarningPayloadForUnsupportedDesktop() {
        let helper = SpaceSwitchPresentationHelper(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository())
        )

        let payload = helper.warningPayload(for: .unsupportedDesktop(index: 10))

        XCTAssertEqual(
            payload,
            .init(
                title: "Desktop 10 can't be switched",
                message: "StayHere can switch only desktops 1 through 9 using Mission Control shortcuts."
            )
        )
    }

    func testWarningPayloadForSwitchUnmatched() {
        let helper = SpaceSwitchPresentationHelper(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository())
        )

        let payload = helper.warningPayload(for: .switchUnmatched(index: 2, expectedSpaceID: 200, actualSpaceID: 100))

        XCTAssertEqual(payload?.title, "Desktop 2 didn't switch")
        XCTAssertTrue(payload?.message.contains("Switch to Desktop 2") == true)
    }

    func testOpenKeyboardShortcutsSettingsFallsBackToSystemSettingsApp() {
        var openedURLs: [URL] = []
        var openedSystemSettings = false
        let helper = SpaceSwitchPresentationHelper(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository()),
            activateApp: {},
            openURL: { url in
                openedURLs.append(url)
                return false
            },
            openSystemSettingsApp: { openedSystemSettings = true }
        )

        helper.openKeyboardShortcutsSettings()

        XCTAssertEqual(openedURLs.count, 1)
        XCTAssertTrue(openedSystemSettings)
    }
}
