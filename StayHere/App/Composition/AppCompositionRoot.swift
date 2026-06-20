import AppKit
import Core
import Activation

@MainActor
final class AppCompositionRoot: NSObject {
    private let services:       CompositionServices
    private let controllers:    CompositionControllers
    private let windowManagers: CompositionWindowManagers
    private let updateController: UpdateController

    let runtimeCoordinator: AppRuntimeCoordinator

    init(
        settings: SettingsRepository = UserDefaultsSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        updateService: (any UpdateService)? = nil
    ) {
        self.services = CompositionServices(
            settings: settings,
            cgsBridge: cgsBridge,
            updateService: updateService
        )
        self.controllers = CompositionControllers(services: services)
        self.windowManagers = CompositionWindowManagers(services: services)
        self.updateController = UpdateController(
            settings: services.settings,
            updateService: services.updateService,
            updateWindowManager: windowManagers.updateWindowManager,
            appearanceManager: services.appearanceManager,
            setAvailableUpdate: { [controllers] updateInfo in
                controllers.statusController.setAvailableUpdate(updateInfo)
                controllers.spaceSwitcherController.setAvailableUpdate(updateInfo)
                controllers.windowSwitcherController.setAvailableUpdate(updateInfo)
                controllers.allSpacesWindowSwitcherController.setAvailableUpdate(updateInfo)
            }
        )
        self.runtimeCoordinator = AppRuntimeCoordinator(
            services: services,
            controllers: controllers,
            windowManagers: windowManagers,
            updateController: updateController,
            setupRequirementsPresenter: controllers.setupRequirementsPresenter
        )
        super.init()
        controllers.setOnOpenUpdateForSwitchers { [weak updateController] in
            updateController?.presentAvailableUpdate()
        }
    }
}
