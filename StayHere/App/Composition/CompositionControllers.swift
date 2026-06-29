import AppKit
import Core
import Activation

@MainActor
final class CompositionControllers {
    let services: CompositionServices

    let statusController: StatusBarController
    let hudController: HUDController
    let switchPresentationHelper: SpaceSwitchPresentationHelper
    let setupRequirementsPresenter: SetupRequirementsPresenter
    let spaceSwitcherController: SpaceSwitcherController
    let windowSwitcherController: WindowSwitcherController
    let allSpacesWindowSwitcherController: WindowSwitcherController
    let hotCornerController: HotCornerController
    let activationController: ActivationController

    private let windowRecencyTracker: WindowRecencyTracker
    private let currentSpaceListProvider: WindowListProvider
    private let allSpacesListProvider: WindowListProvider
    private let currentSpaceWindowSwitchUseCase: WindowSwitchUseCase
    private let allSpacesWindowSwitchUseCase: WindowSwitchUseCase

    init(services: CompositionServices, switchToSpace: @escaping (Int) -> Void) {
        self.services = services

        statusController = StatusBarController(
            settings: services.settings,
            appearanceManager: services.appearanceManager
        )

        hudController = HUDController(
            settings: services.settings,
            appearanceManager: services.appearanceManager
        )

        switchPresentationHelper = SpaceSwitchPresentationHelper(
            appearanceManager: services.appearanceManager
        )

        windowRecencyTracker = WindowRecencyTracker()

        currentSpaceListProvider = WindowListProvider(
            registry: services.repository,
            cgsBridge: services.cgsBridge,
            settings: services.settings
        )

        allSpacesListProvider = WindowListProvider(
            registry: services.repository,
            cgsBridge: services.cgsBridge,
            settings: services.settings
        )

        currentSpaceWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: services.cgsBridge,
            listProvider: currentSpaceListProvider,
            switchSpace: services.switchSpace,
            refreshSpaces: services.refreshSpaces,
            focusService: WindowFocusService()
        ))

        allSpacesWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: services.cgsBridge,
            listProvider: allSpacesListProvider,
            switchSpace: services.switchSpace,
            refreshSpaces: services.refreshSpaces,
            focusService: WindowFocusService()
        ))

        windowSwitcherController = WindowSwitcherController(
            settings: services.settings,
            registry: services.repository,
            mode: .currentSpace,
            windowSwitchUseCase: currentSpaceWindowSwitchUseCase,
            cgsBridge: services.cgsBridge,
            listProvider: currentSpaceListProvider,
            recencyTracker: windowRecencyTracker
        )

        allSpacesWindowSwitcherController = WindowSwitcherController(
            settings: services.settings,
            registry: services.repository,
            mode: .allSpaces,
            windowSwitchUseCase: allSpacesWindowSwitchUseCase,
            cgsBridge: services.cgsBridge,
            listProvider: allSpacesListProvider,
            recencyTracker: windowRecencyTracker
        )

        setupRequirementsPresenter = SetupRequirementsPresenter(
            appearanceManager: services.appearanceManager,
            switchPresentationHelper: switchPresentationHelper,
            logger: services.logger
        )

        spaceSwitcherController = SpaceSwitcherController(
            settings: services.settings,
            registry: services.repository,
            switchToSpace: switchToSpace
        )

        hotCornerController = HotCornerController(
            settings: services.settings,
            actionHandler: { [spaceSwitcher = spaceSwitcherController, windowSwitcher = windowSwitcherController, allSpacesWindowSwitcher = allSpacesWindowSwitcherController] action in
                switch action {
                case .none:
                    break
                case .spaceSwitcher:
                    spaceSwitcher.openSwitcher()
                case .windowSwitcher:
                    windowSwitcher.openSwitcher()
                case .allSpacesWindowSwitcher:
                    allSpacesWindowSwitcher.openSwitcher()
                }
            }
        )

        activationController = ActivationController(
            settings: services.settings,
            windowIndex: WindowIndex(cgsBridge: services.cgsBridge),
            currentSpaceID: { [services] in
                services.repository.activeSpaceID
            },
            activeSpaceIDs: { [services] in
                guard let id = services.repository.activeSpaceID else { return [] }
                return Set([id])
            },
            switchToSpace: switchToSpace,
            onShowSingleWindowHint: { [hud = hudController] message in
                hud.show(message: message)
            },
            logger: services.logger
        )
    }

    func setOnOpenUpdateForSwitchers(_ handler: @escaping () -> Void) {
        spaceSwitcherController.setOnOpenUpdate(handler)
        windowSwitcherController.setOnOpenUpdate(handler)
        allSpacesWindowSwitcherController.setOnOpenUpdate(handler)
    }
}
