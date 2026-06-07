import XCTest
import AppKit
import Core
@testable import StayHereApp

final class SettingsWindowManagerTests: XCTestCase {
    func testShowSettingsCreatesWindowAndPromotesActivationPolicy() {
        let defaults = UserDefaultsSettingsRepository()
        let appearanceManager = AppearanceManager(settings: defaults)
        var setPolicies: [NSApplication.ActivationPolicy] = []
        var activated = false
        let manager = SettingsWindowManager(
            settings: defaults,
            appearanceManager: appearanceManager,
            onAppearanceChange: {},
            setActivationPolicy: { setPolicies.append($0) },
            activateApp: { activated = true },
            hasVisibleOwnedWindow: { false }
        )
        var refreshCount = 0

        manager.showSettings {
            refreshCount += 1
        }

        XCTAssertTrue(manager.isOpen)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(setPolicies.last, .regular)
        XCTAssertTrue(activated)
    }

    func testWindowWillCloseCommitsSettingsAndDemotesWhenNoWindowsRemain() throws {
        let defaults = UserDefaultsSettingsRepository()
        let appearanceManager = AppearanceManager(settings: defaults)
        var setPolicies: [NSApplication.ActivationPolicy] = []
        var didClose = false
        let manager = SettingsWindowManager(
            settings: defaults,
            appearanceManager: appearanceManager,
            onAppearanceChange: {},
            onDidClose: { didClose = true },
            setActivationPolicy: { setPolicies.append($0) },
            activateApp: {},
            hasVisibleOwnedWindow: { false }
        )

        manager.showSettings {}
        manager.settingsCoordinator?.appearanceMode = .dark
        let window = try XCTUnwrap(manager.settingsWindow)

        manager.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertFalse(manager.isOpen)
        XCTAssertTrue(didClose)
        XCTAssertEqual(defaults.appearanceMode, .dark)
        XCTAssertEqual(setPolicies.last, .accessory)
    }
}
