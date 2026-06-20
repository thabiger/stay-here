import XCTest
import Core
@testable import StayHereApp

@MainActor
final class StatusBarControllerTests: XCTestCase {
    private final class MockBridge: CGSBridgeProtocol {
        var activeSpaceIDValue: Int?
        var managedSnapshotValue: CGSBridge.ManagedSnapshot

        init(
            activeSpaceIDValue: Int? = nil,
            managedSnapshotValue: CGSBridge.ManagedSnapshot = CGSBridge.ManagedSnapshot(
                spaces: [],
                activeByDisplay: [:],
                orderedIDsByDisplay: [:]
            )
        ) {
            self.activeSpaceIDValue = activeSpaceIDValue
            self.managedSnapshotValue = managedSnapshotValue
        }

        func activeSpaceID() -> Int? { activeSpaceIDValue }
        func managedSnapshot() -> CGSBridge.ManagedSnapshot { managedSnapshotValue }
        func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
        func switchByDesktopShortcut(index: Int) -> Bool { true }
        func spacesForWindow(windowID: Int) -> [Int] { [] }
    }

    private func makeRegistry() -> SpaceRegistry {
        let bridge = MockBridge(
            activeSpaceIDValue: 1,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [SpaceIdentity(id: 1, display: "Main", kind: .desktop)],
                activeByDisplay: ["Main": 1],
                orderedIDsByDisplay: ["Main": [1]]
            )
        )
        let store = SpaceStore()
        return SpaceRegistry(store: store, cgsBridge: bridge, logger: NoOpLogger())
    }

    func testMenuContainsCheckForUpdatesByDefault() {
        let settings = UserDefaultsSettingsRepository()
        let controller = StatusBarController(
            settings: settings,
            appearanceManager: AppearanceManager(settings: settings)
        )

        controller.configure(
            registry: makeRegistry(),
            onOpenSettings: {},
            onOpenAbout: {},
            onCheckForUpdates: {},
            onOpenAvailableUpdate: {},
            onCopyState: {},
            onOpenLogs: {},
            onQuit: {},
            onSelectSpace: { _ in },
            onRenameSpace: { _, _ in }
        )

        XCTAssertTrue(controller.debugMenuItemTitles.contains("Check for Updates…"))
        XCTAssertFalse(controller.debugMenuItemTitles.contains("Update Available…"))
    }

    func testMenuAddsUpdateAvailableEntryWhenUpdateExists() {
        let settings = UserDefaultsSettingsRepository()
        let controller = StatusBarController(
            settings: settings,
            appearanceManager: AppearanceManager(settings: settings)
        )

        controller.configure(
            registry: makeRegistry(),
            onOpenSettings: {},
            onOpenAbout: {},
            onCheckForUpdates: {},
            onOpenAvailableUpdate: {},
            onCopyState: {},
            onOpenLogs: {},
            onQuit: {},
            onSelectSpace: { _ in },
            onRenameSpace: { _, _ in }
        )

        controller.setAvailableUpdate(
            UpdateInfo(
                version: "0.2.0",
                releaseURL: URL(string: "https://example.com/release")!,
                downloadURL: URL(string: "https://example.com/download")!,
                title: "StayHere 0.2.0",
                notes: "Release notes",
                publishedAt: Date()
            )
        )

        XCTAssertTrue(controller.debugMenuItemTitles.contains("Update Available…"))
    }
}
