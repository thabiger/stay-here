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

    /// Intentionally shared by both window switchers so MRU ordering stays
    /// consistent regardless of which switcher committed the selection
    /// (e.g. picking a current-space window from the all-spaces switcher
    /// also moves it to the front of the current-space switcher).
    /// Strongly retained by both WindowSwitcherController instances;
    /// kept here to make the sharing explicit. Do NOT split without a
    /// deliberate product decision.
    private let sharedWindowRecencyTracker: WindowRecencyTracker

    init(services: CompositionServices, switchToSpace: @escaping (Int) -> Void) {
        self.services = services

        statusController = Self.makeStatusBarController(services: services)
        hudController = Self.makeHUDController(services: services)
        switchPresentationHelper = Self.makeSwitchPresentationHelper(services: services)
        setupRequirementsPresenter = Self.makeSetupRequirementsPresenter(
            services: services,
            switchPresentationHelper: switchPresentationHelper
        )

        let pair = Self.makeWindowSwitcherPair(services: services)
        sharedWindowRecencyTracker = pair.recencyTracker
        windowSwitcherController = pair.currentSpace
        allSpacesWindowSwitcherController = pair.allSpaces

        spaceSwitcherController = Self.makeSpaceSwitcherController(
            services: services,
            switchToSpace: switchToSpace
        )

        let hotCornerDispatcher = HotCornerSwitcherDispatcher(
            spaceSwitcher: spaceSwitcherController,
            windowSwitcher: windowSwitcherController,
            allSpacesWindowSwitcher: allSpacesWindowSwitcherController
        )
        hotCornerController = Self.makeHotCornerController(
            services: services,
            actionHandler: hotCornerDispatcher
        )

        activationController = Self.makeActivationController(
            services: services,
            hud: hudController,
            switchToSpace: switchToSpace
        )
    }

    func setOnOpenUpdateForSwitchers(_ handler: @escaping () -> Void) {
        spaceSwitcherController.setOnOpenUpdate(handler)
        windowSwitcherController.setOnOpenUpdate(handler)
        allSpacesWindowSwitcherController.setOnOpenUpdate(handler)
    }

    // MARK: - Factories

    private struct WindowSwitcherPair {
        let currentSpace: WindowSwitcherController
        let allSpaces: WindowSwitcherController
        let recencyTracker: WindowRecencyTracker
    }

    private static func makeStatusBarController(services: CompositionServices) -> StatusBarController {
        StatusBarController(
            settings: services.settings,
            appearanceManager: services.appearanceManager
        )
    }

    private static func makeHUDController(services: CompositionServices) -> HUDController {
        HUDController(
            settings: services.settings,
            appearanceManager: services.appearanceManager
        )
    }

    private static func makeSwitchPresentationHelper(services: CompositionServices) -> SpaceSwitchPresentationHelper {
        SpaceSwitchPresentationHelper(
            appearanceManager: services.appearanceManager
        )
    }

    private static func makeSetupRequirementsPresenter(
        services: CompositionServices,
        switchPresentationHelper: SpaceSwitchPresentationHelper
    ) -> SetupRequirementsPresenter {
        SetupRequirementsPresenter(
            appearanceManager: services.appearanceManager,
            switchPresentationHelper: switchPresentationHelper,
            logger: services.logger
        )
    }

    private static func makeWindowSwitcherPair(services: CompositionServices) -> WindowSwitcherPair {
        let recencyTracker = WindowRecencyTracker()

        let currentSpaceListProvider = WindowListProvider(
            registry: services.queryService,
            cgsBridge: services.cgsBridge,
            settings: services.settings
        )

        let allSpacesListProvider = WindowListProvider(
            registry: services.queryService,
            cgsBridge: services.cgsBridge,
            settings: services.settings
        )

        let currentSpaceWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: services.cgsBridge,
            listProvider: currentSpaceListProvider,
            switchSpace: services.switchSpace,
            refreshSpaces: services.refreshSpaces,
            focusService: WindowFocusService()
        ))

        let allSpacesWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: services.cgsBridge,
            listProvider: allSpacesListProvider,
            switchSpace: services.switchSpace,
            refreshSpaces: services.refreshSpaces,
            focusService: WindowFocusService()
        ))

        let windowSwitcherController = WindowSwitcherController(
            settings: services.settings,
            registry: services.queryService,
            mode: .currentSpace,
            windowSwitchUseCase: currentSpaceWindowSwitchUseCase,
            cgsBridge: services.cgsBridge,
            dependencies: WindowSwitcherDependencies(listProvider: currentSpaceListProvider, recencyTracker: recencyTracker)
        )

        let allSpacesWindowSwitcherController = WindowSwitcherController(
            settings: services.settings,
            registry: services.queryService,
            mode: .allSpaces,
            windowSwitchUseCase: allSpacesWindowSwitchUseCase,
            cgsBridge: services.cgsBridge,
            dependencies: WindowSwitcherDependencies(listProvider: allSpacesListProvider, recencyTracker: recencyTracker)
        )

        return WindowSwitcherPair(
            currentSpace: windowSwitcherController,
            allSpaces: allSpacesWindowSwitcherController,
            recencyTracker: recencyTracker
        )
    }

    private static func makeSpaceSwitcherController(
        services: CompositionServices,
        switchToSpace: @escaping (Int) -> Void
    ) -> SpaceSwitcherController {
        SpaceSwitcherController(
            settings: services.settings,
            registry: services.queryService,
            switchToSpace: switchToSpace
        )
    }

    private static func makeHotCornerController(
        services: CompositionServices,
        actionHandler: any HotCornerActionHandling
    ) -> HotCornerController {
        HotCornerController(
            settings: services.settings,
            actionHandler: actionHandler
        )
    }

    /// Hidden concrete deps behind closures: `hud` (onShowSingleWindowHint),
    /// `services.queryService.activeSpaceID` (currentSpaceID/activeSpaceIDs).
    /// These closures are the Activation module's designed seam — keep them visible here.
    private static func makeActivationController(
        services: CompositionServices,
        hud: HUDController,
        switchToSpace: @escaping (Int) -> Void
    ) -> ActivationController {
        let windowIndex = WindowIndex(cgsBridge: services.cgsBridge)
        return ActivationController(
            settings: services.settings,
            windowIndex: windowIndex,
            currentSpaceID: { [services] in
                services.queryService.activeSpaceID
            },
            activeSpaceIDs: { [services] in
                guard let id = services.queryService.activeSpaceID else { return [] }
                return Set([id])
            },
            switchToSpace: switchToSpace,
            onShowSingleWindowHint: { [hud] message in
                hud.show(message: message)
            },
            logger: services.logger
        )
    }
}
