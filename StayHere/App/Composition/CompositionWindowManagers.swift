import AppKit
import Core

@MainActor
final class CompositionWindowManagers {
    let services: CompositionServices
    weak var runtimeCoordinator: (any RuntimeCoordinating)?

    lazy var settingsWindowManager = SettingsWindowManager(
        settings: services.settings,
        appearanceManager: services.appearanceManager,
        onAppearanceChange: { [weak self] in
            self?.runtimeCoordinator?.applyAppearanceImmediately()
        }
    )

    lazy var aboutWindowManager = AboutWindowManager(
        appearanceManager: services.appearanceManager
    )

    lazy var updateWindowManager = UpdateWindowManager(
        appearanceManager: services.appearanceManager
    )

    init(services: CompositionServices) {
        self.services = services
    }
}
