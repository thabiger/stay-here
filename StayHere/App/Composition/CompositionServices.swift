import AppKit
import Core
import Activation

@MainActor
final class CompositionServices {
    let settings: SettingsRepository
    let cgsBridge: any CGSBridgeProtocol
    let appearanceManager: AppearanceManager
    let lifecycleCoordinator: AppLifecycleCoordinator
    let updateService: any UpdateService
    let registry: SpaceRegistry
    let logger: any Logging

    init(
        settings: SettingsRepository = UserDefaultsSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        updateService: (any UpdateService)? = nil,
        lifecycleCoordinator: AppLifecycleCoordinator? = nil,
        logger: any Logging
    ) {
        self.settings = settings
        self.cgsBridge = cgsBridge
        self.updateService = updateService ?? GitHubReleaseUpdateService()
        self.appearanceManager = AppearanceManager(settings: settings)
        self.logger = logger
        self.lifecycleCoordinator = lifecycleCoordinator ?? AppLifecycleCoordinator(
            appearanceManager: self.appearanceManager,
            logger: logger
        )
        self.registry = SpaceRegistry(cgsBridge: cgsBridge, logger: logger)
    }
}
