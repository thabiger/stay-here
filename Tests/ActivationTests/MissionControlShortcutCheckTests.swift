import XCTest
import Core

final class MissionControlShortcutCheckTests: XCTestCase {
    func testMissionControlShortcutCheckPassesWhenControlNumberShortcutsAreEnabled() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123]), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutCheck.check(defaults: defaults)

        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.warningMessage)
    }

    func testMissionControlShortcutCheckReportsMissingOrMismatchedShortcuts() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            makeHotKeys(
                enabledIDs: [118, 119, 120],
                remappedID: 121,
                remappedKeyCode: 24
            ),
            forKey: "AppleSymbolicHotKeys"
        )

        let result = MissionControlShortcutCheck.check(defaults: defaults)

        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(
            result.missingDescriptions,
            [
                "Desktop 4 is not set to Control+4",
                "Desktop 5 is not set to Control+5",
                "Desktop 6 is not set to Control+6"
            ]
        )
        XCTAssertNotNil(result.warningMessage)
    }

    private func makeHotKeys(
        enabledIDs: [Int],
        remappedID: Int? = nil,
        remappedKeyCode: Int? = nil
    ) -> [String: Any] {
        let allIDs = [118, 119, 120, 121, 122, 123]
        var hotKeys: [String: Any] = [:]

        for id in allIDs {
            let isEnabled = enabledIDs.contains(id)
            var entry: [String: Any] = ["enabled": isEnabled ? 1 : 0]
            if isEnabled || id == remappedID {
                let keyCode = id == remappedID ? (remappedKeyCode ?? 18) : keyCode(for: id)
                entry["value"] = [
                    "parameters": [65535, keyCode, 262144],
                    "type": "standard"
                ]
            }
            hotKeys[String(id)] = entry
        }

        return hotKeys
    }

    private func keyCode(for id: Int) -> Int {
        switch id {
        case 118: return 18
        case 119: return 19
        case 120: return 20
        case 121: return 21
        case 122: return 23
        case 123: return 22
        default: return 18
        }
    }
}
