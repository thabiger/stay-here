import AppKit
import Core
import Activation

@MainActor
private final class AppRuntimeCallbackSink {
    weak var coordinator: AppRuntimeCoordinator?

    func applyAppearanceImmediately() {
        coordinator?.applyAppearanceImmediately()
    }

    func pauseBackgroundUpdates() {
        coordinator?.pauseBackgroundUpdates()
    }

    func settingsWindowDidClose() {
        coordinator?.settingsWindowDidClose()
    }

    func performSpaceSwitch(_ spaceID: Int) {
        coordinator?.performSpaceSwitch(spaceID)
    }
}

@MainActor
final class AppCompositionRoot: NSObject {
    let settings: SettingsRepository
    let cgsBridge: any CGSBridgeProtocol
    let appearanceManager: AppearanceManager
    let lifecycleCoordinator: AppLifecycleCoordinator
    private let runtimeCallbackSink = AppRuntimeCallbackSink()

    lazy var registry = SpaceRegistry(cgsBridge: cgsBridge)
    lazy var statusController = StatusBarController(
        settings: settings,
        appearanceManager: appearanceManager
    )
    lazy var hudController = HUDController(
        settings: settings,
        appearanceManager: appearanceManager
    )
    lazy var switchPresentationHelper = SpaceSwitchPresentationHelper(
        appearanceManager: appearanceManager
    )
    lazy var setupRequirementsPresenter = SetupRequirementsPresenter(
        appearanceManager: appearanceManager,
        switchPresentationHelper: switchPresentationHelper
    )
    lazy var settingsWindowManager = SettingsWindowManager(
        settings: settings,
        appearanceManager: appearanceManager,
        onAppearanceChange: { [weak self] in
            self?.runtimeCallbackSink.applyAppearanceImmediately()
        },
        onWillOpen: { [weak self] in
            self?.runtimeCallbackSink.pauseBackgroundUpdates()
        },
        onDidClose: { [weak self] in
            self?.runtimeCallbackSink.settingsWindowDidClose()
        }
    )
    lazy var activationController = ActivationController(
        settings: settings,
        windowIndex: WindowIndex(cgsBridge: cgsBridge),
        currentSpaceID: { [weak self] in
            self?.registry.activeSpaceID
        },
        activeSpaceIDs: { [weak self] in
            guard let id = self?.registry.activeSpaceID else { return [] }
            return Set([id])
        },
        switchToSpace: { [weak self] spaceID in
            self?.runtimeCallbackSink.performSpaceSwitch(spaceID)
        },
        onShowSingleWindowHint: { [weak self] message in
            self?.hudController.show(message: message)
        }
    )
    lazy var spaceSwitcherController = SpaceSwitcherController(
        settings: settings,
        registry: registry,
        switchToSpace: { [weak self] spaceID in
            self?.runtimeCallbackSink.performSpaceSwitch(spaceID)
        }
    )
    lazy var windowSwitcherController = WindowSwitcherController(
        settings: settings,
        registry: registry,
        cgsBridge: cgsBridge
    )
    lazy var runtimeCoordinator = AppRuntimeCoordinator(
        settings: settings,
        appearanceManager: appearanceManager,
        lifecycleCoordinator: lifecycleCoordinator,
        registry: registry,
        statusController: statusController,
        hudController: hudController,
        settingsWindowManager: settingsWindowManager,
        activationController: activationController,
        spaceSwitcherController: spaceSwitcherController,
        windowSwitcherController: windowSwitcherController,
        switchPresentationHelper: switchPresentationHelper,
        setupRequirementsPresenter: setupRequirementsPresenter
    )

    init(
        settings: SettingsRepository = UserDefaultsSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live
    ) {
        self.settings = settings
        self.cgsBridge = cgsBridge
        self.appearanceManager = AppearanceManager(settings: settings)
        self.lifecycleCoordinator = AppLifecycleCoordinator(
            appearanceManager: self.appearanceManager
        )
        super.init()
        runtimeCallbackSink.coordinator = runtimeCoordinator
    }
}
