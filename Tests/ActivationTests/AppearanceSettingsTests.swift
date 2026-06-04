import XCTest
import Core

final class AppearanceSettingsTests: XCTestCase {
    func testDefaultModeIsSystem() {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.mode, .system)
    }

    func testPersistsMode() {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppearanceSettings(defaults: defaults)
        settings.mode = .dark

        let reread = AppearanceSettings(defaults: defaults)
        XCTAssertEqual(reread.mode, .dark)
    }

    func testIgnoresInvalidStoredValue() {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("banana", forKey: "appearance.mode")

        let settings = AppearanceSettings(defaults: defaults)

        XCTAssertEqual(settings.mode, .system)
    }
}
