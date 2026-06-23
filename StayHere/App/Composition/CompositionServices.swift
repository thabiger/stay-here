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
    let repository: SpaceStateManager
    let registry: SpaceRegistry
    let refreshSpaces: RefreshSpacesUseCase
    let renameSpace: RenameSpaceUseCase
    let reorderSpaces: ReorderSpacesUseCase
    let switchSpace: SwitchSpaceUseCase
    let buildSpaceSnapshot: BuildSpaceSnapshotUseCase
    let logger: any Logging

    init(
        settings: SettingsRepository = UserDefaultsSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol,
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
        self.repository = SpaceStateManager(cgsBridge: cgsBridge, logger: logger)
        self.refreshSpaces = RefreshSpacesUseCase(
            repository: self.repository,
            logger: logger
        )
        self.renameSpace = RenameSpaceUseCase(repository: self.repository)
        self.reorderSpaces = ReorderSpacesUseCase(repository: self.repository)
        self.switchSpace = SwitchSpaceUseCase(
            cgsBridge: cgsBridge,
            repository: self.repository,
            refreshUseCase: self.refreshSpaces,
            logger: logger
        )
        self.buildSpaceSnapshot = BuildSpaceSnapshotUseCase(repository: self.repository)
        self.registry = SpaceRegistry(repository: self.repository)
    }
}
