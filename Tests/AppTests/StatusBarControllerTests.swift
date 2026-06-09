import XCTest
import Core
@testable import StayHereApp

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testMenuContainsCheckForUpdatesByDefault() {
        let settings = UserDefaultsSettingsRepository()
        let controller = StatusBarController(
            settings: settings,
            appearanceManager: AppearanceManager(settings: settings)
        )

        controller.configure(
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
