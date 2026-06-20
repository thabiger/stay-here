import AppKit
import Core

@MainActor
final class WindowCoordinator {
    private let settingsWindowManager: SettingsWindowManager
    private let aboutWindowManager: AboutWindowManager
    private let appearanceManager: AppearanceManager
    private let registry: SpaceRegistry
    private let settings: SettingsRepository

    var onSettingsWillOpen: (() -> Void)?
    var onSettingsDidClose: (() -> Void)?

    init(
        settingsWindowManager: SettingsWindowManager,
        aboutWindowManager: AboutWindowManager,
        appearanceManager: AppearanceManager,
        registry: SpaceRegistry,
        settings: SettingsRepository
    ) {
        self.settingsWindowManager = settingsWindowManager
        self.aboutWindowManager = aboutWindowManager
        self.appearanceManager = appearanceManager
        self.registry = registry
        self.settings = settings

        self.settingsWindowManager.onWillOpen = { [weak self] in
            self?.handleSettingsWillOpen()
        }
        self.settingsWindowManager.onDidClose = { [weak self] in
            self?.handleSettingsDidClose()
        }
    }

    var isSettingsOpen: Bool {
        settingsWindowManager.isOpen
    }

    func showSettings() {
        settingsWindowManager.showSettings(refreshRegistry: { [weak self] in
            self?.registry.refreshSpaces()
        })
    }

    func showAbout() {
        aboutWindowManager.showAbout()
    }

    func applyAppearanceImmediately() {
        appearanceManager.applyCurrentMode()
    }

    private func handleSettingsWillOpen() {
        onSettingsWillOpen?()
    }

    private func handleSettingsDidClose() {
        applyAppearanceImmediately()
        onSettingsDidClose?()
        statusBarItemsDidClose()
    }

    private func statusBarItemsDidClose() {
        registry.refreshSpaces()
    }
}
