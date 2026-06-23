import XCTest
import Core

final class MissionControlShortcutCheckTests: XCTestCase {
    func testMissionControlShortcutCheckPassesWhenControlNumberShortcutsAreEnabled() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123, 124, 125, 126]), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutCheck.check(desktopCount: 9, defaults: defaults, cgsBridge: MockCGSBridge())

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

        let result = MissionControlShortcutCheck.check(desktopCount: 9, defaults: defaults, cgsBridge: MockCGSBridge())

        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(
            result.missingDescriptions,
            ["Mission Control shortcuts Control+1 through Control+9 are not fully enabled"]
        )
        XCTAssertNotNil(result.warningMessage)
        XCTAssertEqual(result.itemStatuses.count, 1)
        XCTAssertEqual(result.itemStatuses.first?.displayName, "Mission Control shortcuts: Control+1 through Control+9")
    }

    func testMissionControlShortcutCheckFallsBackToSystemPlistShape() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissionControlShortcutCheckTests.\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let root: [String: Any] = [
            "AppleSymbolicHotKeys": makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123, 124, 125, 126])
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        try data.write(to: tempURL, options: .atomic)

        let result = MissionControlShortcutCheck.check(desktopCount: 9, preferencesURL: tempURL, cgsBridge: MockCGSBridge())

        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.warningMessage)
    }

    func testMissionControlShortcutCheckOnlyRequiresExistingDesktops() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120]), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutCheck.check(desktopCount: 3, defaults: defaults, cgsBridge: MockCGSBridge())

        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.warningMessage)
        XCTAssertEqual(result.itemStatuses.first?.displayName, "Mission Control shortcuts: Control+1 through Control+3")
    }

    func testDesktopShortcutCheckReportsSpecificMissingDesktopShortcut() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120, 122, 123]), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutCheck.checkShortcut(forDesktopIndex: 4, defaults: defaults)

        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(result.missingDescriptions, ["Desktop 4 is not set to Control+4"])
        XCTAssertEqual(
            result.warningMessage,
            "Desktop 4 cannot be switched because Mission Control shortcut Control+4 is disabled or changed. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control and enable \"Switch to Desktop 4\"."
        )
    }

    func testDesktopShortcutCheckPassesWhenSpecificDesktopShortcutIsEnabled() {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123]), forKey: "AppleSymbolicHotKeys")

        let result = MissionControlShortcutCheck.checkShortcut(forDesktopIndex: 4, defaults: defaults)

        XCTAssertTrue(result.isSatisfied)
        XCTAssertNil(result.warningMessage)
    }

    func testDesktopShortcutCheckPrefersPreferencesFileOverStaleDefaultsSnapshot() throws {
        let suiteName = "MissionControlShortcutCheckTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123, 124, 125, 126]),
            forKey: "AppleSymbolicHotKeys"
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissionControlShortcutCheckTests.\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let root: [String: Any] = [
            "AppleSymbolicHotKeys": makeHotKeys(enabledIDs: [118, 119, 120, 121, 122, 123, 124])
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        try data.write(to: tempURL, options: .atomic)

        let result = MissionControlShortcutCheck.checkShortcut(
            forDesktopIndex: 8,
            defaults: defaults,
            preferencesURL: tempURL
        )

        XCTAssertFalse(result.isSatisfied)
        XCTAssertEqual(result.missingDescriptions, ["Desktop 8 is not set to Control+8"])
    }

    private func makeHotKeys(
        enabledIDs: [Int],
        remappedID: Int? = nil,
        remappedKeyCode: Int? = nil
    ) -> [String: Any] {
        let allIDs = [118, 119, 120, 121, 122, 123, 124, 125, 126]
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
        case 124: return 26
        case 125: return 28
        case 126: return 25
        default: return 18
        }
    }
}
