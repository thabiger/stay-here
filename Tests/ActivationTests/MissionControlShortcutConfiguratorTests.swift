import XCTest
import Core

final class MissionControlShortcutConfiguratorTests: XCTestCase {
    func testConfiguratorSeedsMissingShortcuts() {
        let suiteName = "MissionControlShortcutConfiguratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["118": ["enabled": 0]], forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutConfigurator.ensureControlNumberShortcutsEnabled(defaults: defaults)

        XCTAssertTrue(result.changed)
        XCTAssertTrue(result.isSatisfied)

        let check = MissionControlShortcutCheck.check(defaults: defaults)
        XCTAssertTrue(check.isSatisfied)
    }

    func testConfiguratorLeavesMatchingShortcutsUntouched() {
        let suiteName = "MissionControlShortcutConfiguratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutConfigurator.ensureControlNumberShortcutsEnabled(defaults: defaults)

        XCTAssertFalse(result.changed)
        XCTAssertTrue(result.isSatisfied)
    }

    private func makeHotKeys() -> [String: Any] {
        let shortcuts: [(Int, Int)] = [
            (118, 18),
            (119, 19),
            (120, 20),
            (121, 21),
            (122, 23),
            (123, 22),
            (124, 26),
            (125, 28),
            (126, 25),
        ]

        var hotKeys: [String: Any] = [:]
        for (id, keyCode) in shortcuts {
            hotKeys[String(id)] = [
                "enabled": 1,
                "value": [
                    "parameters": [65535, keyCode, 262144],
                    "type": "standard"
                ]
            ]
        }
        return hotKeys
    }
}
