import AppKit
import Core
import Activation

@MainActor
final class AppCompositionRoot: NSObject {
    private let services:           CompositionServices
    private let updateController:   UpdateController

    let runtimeCoordinator: AppRuntimeCoordinator

    init(
        settings: SettingsRepository = CompositeSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol,
        updateService: (any UpdateService)? = nil
    ) {
        let logger: any Logging = FileLogger(
            isInfoEnabled: { [weak settings] in settings?.diagnosticsEnabled ?? false }
        )
        self.services = CompositionServices(
            settings: settings,
            cgsBridge: cgsBridge,
            updateService: updateService,
            logger: logger
        )

        let aboutWindowManager = AboutWindowManager(
            appearanceManager: services.appearanceManager
        )
        let updateWindowManager = UpdateWindowManager(
            appearanceManager: services.appearanceManager
        )

        self.runtimeCoordinator = AppRuntimeCoordinator(
            services: services,
            aboutWindowManager: aboutWindowManager,
            updateWindowManager: updateWindowManager
        )

        let controllers = runtimeCoordinator.controllers
        let windowManagers = runtimeCoordinator.windowManagers

        self.updateController = UpdateController(
            settings: services.settings,
            updateService: services.updateService,
            updateWindowManager: windowManagers.updateWindowManager,
            alertPresenter: windowManagers.updateWindowManager,
            setAvailableUpdate: { [controllers] updateInfo in
                controllers.statusController.setAvailableUpdate(updateInfo)
                controllers.spaceSwitcherController.setAvailableUpdate(updateInfo)
                controllers.windowSwitcherController.setAvailableUpdate(updateInfo)
                controllers.allSpacesWindowSwitcherController.setAvailableUpdate(updateInfo)
            },
            logger: logger
        )

        runtimeCoordinator.setUpdateController(updateController)

        let eventTapProxy = AppEventTapProxy(logger: services.logger)
        let switcherDirector = SwitcherDirector(
            spaceSwitcherController: controllers.spaceSwitcherController,
            windowSwitcherController: controllers.windowSwitcherController,
            allSpacesWindowSwitcherController: controllers.allSpacesWindowSwitcherController,
            settings: services.settings,
            eventTapProxy: eventTapProxy
        )
        let eventOrchestrator = EventOrchestrationCoordinator(
            hotCornerController: controllers.hotCornerController,
            activationController: controllers.activationController,
            switcherDirector: switcherDirector,
            eventTapProxy: eventTapProxy
        )
        runtimeCoordinator.setEventOrchestrator(eventOrchestrator)

        super.init()

        controllers.setOnOpenUpdateForSwitchers { [weak updateController] in
            updateController?.presentAvailableUpdate()
        }
    }
}
