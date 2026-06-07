import XCTest
import Core

final class MissionControlShortcutCheckBridgeTests: XCTestCase {
    func testMissionControlShortcutCheckUsesInjectedBridgeToInferDesktopCount() {
        let suiteName = "MissionControlShortcutCheckBridgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120]), forKey: "AppleSymbolicHotKeys")

        let bridge = MockCGSBridge(
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 11, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 12, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 13, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 99, display: "display-a", kind: .fullscreen)
                ],
                activeByDisplay: ["display-a": 11],
                orderedIDsByDisplay: ["display-a": [11, 12, 13, 99]]
            )
        )

        let result = MissionControlShortcutCheck.check(defaults: defaults, cgsBridge: bridge)

        XCTAssertTrue(result.isSatisfied)
        XCTAssertEqual(result.itemStatuses.first?.displayName, "Mission Control shortcuts: Control+1 through Control+3")
    }

    private func makeHotKeys(enabledIDs: [Int]) -> [String: Any] {
        let allIDs = [118, 119, 120, 121, 122, 123, 124, 125, 126]
        var hotKeys: [String: Any] = [:]

        for id in allIDs {
            let isEnabled = enabledIDs.contains(id)
            hotKeys[String(id)] = [
                "enabled": isEnabled ? 1 : 0,
                "value": [
                    "parameters": [65535, keyCode(for: id), 262144],
                    "type": "standard"
                ]
            ]
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
        case 124: return 26
        case 125: return 28
        case 126: return 25
        default: return 18
        }
    }
}
