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
    let queryService: SpaceQueryService
    let refreshSpaces: RefreshSpacesUseCase
    let renameSpace: RenameSpaceUseCase
    let switchSpace: SwitchSpaceUseCase
    let buildSpaceSnapshot: BuildSpaceSnapshotUseCase
    let logger: any Logging

    init(
        settings: SettingsRepository = CompositeSettingsRepository(),
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
        let stateStore = SpaceStateStore()
        let orderingService = SpaceOrderingService()
        let nameProvider = SpaceDisplayNameProvider()
        let snapshotBuilder = SpaceSnapshotBuilder()
        let persistenceCoordinator = SpacePersistenceCoordinator(
            store: SpaceStore(),
            labelStore: nil,
            logger: logger
        )
        self.repository = SpaceStateManager(
            cgsBridge: cgsBridge,
            stateStore: stateStore,
            persistenceCoordinator: persistenceCoordinator,
            orderingService: orderingService,
            logger: logger
        )
        self.queryService = SpaceQueryService(
            stateStore: stateStore,
            orderingService: orderingService,
            nameProvider: nameProvider,
            snapshotBuilder: snapshotBuilder
        )
        self.refreshSpaces = RefreshSpacesUseCase(
            repository: self.repository,
            logger: logger
        )
        self.renameSpace = RenameSpaceUseCase(renamer: self.repository)
        self.switchSpace = SwitchSpaceUseCase(
            cgsBridge: cgsBridge,
            repository: self.queryService,
            refreshUseCase: self.refreshSpaces,
            logger: logger
        )
        self.buildSpaceSnapshot = BuildSpaceSnapshotUseCase(builder: self.queryService)
    }
}
