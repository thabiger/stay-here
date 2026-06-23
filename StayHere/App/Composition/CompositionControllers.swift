import AppKit
import Core
import Activation

@MainActor
final class CompositionControllers {
    let services: CompositionServices
    weak var runtimeCoordinator: (any RuntimeCoordinating)?

    lazy var statusController = StatusBarController(
        settings: services.settings,
        appearanceManager: services.appearanceManager
    )

    lazy var hudController = HUDController(
        settings: services.settings,
        appearanceManager: services.appearanceManager
    )

    lazy var switchPresentationHelper = SpaceSwitchPresentationHelper(
        appearanceManager: services.appearanceManager
    )

    lazy var setupRequirementsPresenter = SetupRequirementsPresenter(
        appearanceManager: services.appearanceManager,
        switchPresentationHelper: switchPresentationHelper,
        logger: services.logger
    )

    lazy var spaceSwitcherController = SpaceSwitcherController(
        settings: services.settings,
        registry: services.registry,
        switchToSpace: { [weak self] spaceID in
            Task { [weak self] in
                await self?.runtimeCoordinator?.performSpaceSwitch(spaceID)
            }
        }
    )

    private lazy var windowRecencyTracker = WindowRecencyTracker()

    private lazy var currentSpaceListProvider = WindowListProvider(
        registry: services.registry,
        cgsBridge: services.cgsBridge,
        settings: services.settings
    )

    private lazy var allSpacesListProvider = WindowListProvider(
        registry: services.registry,
        cgsBridge: services.cgsBridge,
        settings: services.settings
    )

    private lazy var currentSpaceWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
        cgsBridge: services.cgsBridge,
        listProvider: currentSpaceListProvider,
        switchSpace: services.switchSpace,
        refreshSpaces: services.refreshSpaces,
        focusService: WindowFocusService()
    ))

    private lazy var allSpacesWindowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
        cgsBridge: services.cgsBridge,
        listProvider: allSpacesListProvider,
        switchSpace: services.switchSpace,
        refreshSpaces: services.refreshSpaces,
        focusService: WindowFocusService()
    ))

    lazy var windowSwitcherController = WindowSwitcherController(
        settings: services.settings,
        registry: services.registry,
        mode: .currentSpace,
        windowSwitchUseCase: currentSpaceWindowSwitchUseCase,
        cgsBridge: services.cgsBridge,
        listProvider: currentSpaceListProvider,
        recencyTracker: windowRecencyTracker
    )

    lazy var allSpacesWindowSwitcherController = WindowSwitcherController(
        settings: services.settings,
        registry: services.registry,
        mode: .allSpaces,
        windowSwitchUseCase: allSpacesWindowSwitchUseCase,
        cgsBridge: services.cgsBridge,
        listProvider: allSpacesListProvider,
        recencyTracker: windowRecencyTracker
    )

    lazy var hotCornerController = HotCornerController(
        settings: services.settings,
        actionHandler: { [weak self] action in
            switch action {
            case .none:
                break
            case .spaceSwitcher:
                self?.spaceSwitcherController.openSwitcher()
            case .windowSwitcher:
                self?.windowSwitcherController.openSwitcher()
            case .allSpacesWindowSwitcher:
                self?.allSpacesWindowSwitcherController.openSwitcher()
            }
        }
    )

    lazy var activationController = ActivationController(
        settings: services.settings,
        windowIndex: WindowIndex(cgsBridge: services.cgsBridge),
        currentSpaceID: { [weak self] in
            self?.services.registry.activeSpaceID
        },
        activeSpaceIDs: { [weak self] in
            guard let id = self?.services.registry.activeSpaceID else { return [] }
            return Set([id])
        },
        switchToSpace: { [weak self] spaceID in
            Task { [weak self] in
                await self?.runtimeCoordinator?.performSpaceSwitch(spaceID)
            }
        },
        onShowSingleWindowHint: { [weak self] message in
            self?.hudController.show(message: message)
        },
        logger: services.logger
    )

    init(services: CompositionServices) {
        self.services = services
    }

    func setOnOpenUpdateForSwitchers(_ handler: @escaping () -> Void) {
        spaceSwitcherController.setOnOpenUpdate(handler)
        windowSwitcherController.setOnOpenUpdate(handler)
        allSpacesWindowSwitcherController.setOnOpenUpdate(handler)
    }
}
