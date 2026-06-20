import XCTest
import Core
import Activation
@testable import StayHereApp

@MainActor
final class AppRuntimeCoordinatorUpdateTests: XCTestCase {
    func testLaunchRestoresCachedStateAndSchedulesAutomaticCheck() {
        let updateController = UpdateControllerSpy()
        let settings = UserDefaultsSettingsRepository()
        let appearanceManager = AppearanceManager(settings: settings)
        let cgsBridge = FakeCGSBridge()
        let registry = SpaceRegistry(cgsBridge: cgsBridge)
        let coordinator = AppRuntimeCoordinator(
            settings: settings,
            appearanceManager: appearanceManager,
            lifecycleCoordinator: AppLifecycleCoordinator(
                appearanceManager: appearanceManager,
                applyAppearance: {},
                setupStatusProvider: {
                    AppSetupStatusSnapshot(isSatisfied: true, missingDescriptionsCount: 0)
                },
                setActivationPolicy: { _ in }
            ),
            registry: registry,
            statusController: StatusBarController(
                settings: settings,
                appearanceManager: appearanceManager
            ),
            updateController: updateController,
            hudController: HUDController(
                settings: settings,
                appearanceManager: appearanceManager
            ),
            settingsWindowManager: SettingsWindowManager(
                settings: settings,
                appearanceManager: appearanceManager,
                onAppearanceChange: {},
                setActivationPolicy: { _ in },
                activateApp: {},
                hasVisibleOwnedWindow: { false }
            ),
            aboutWindowManager: AboutWindowManager(
                appearanceManager: appearanceManager,
                setActivationPolicy: { _ in },
                activateApp: {},
                hasVisibleOwnedWindow: { false }
            ),
            activationController: ActivationController(
                settings: settings,
                windowIndex: WindowIndex(cgsBridge: cgsBridge),
                currentSpaceID: { nil },
                activeSpaceIDs: { [] },
                switchToSpace: { _ in },
                onShowSingleWindowHint: { _ in }
            ),
            spaceSwitcherController: SpaceSwitcherController(
                settings: settings,
                registry: registry,
                switchToSpace: { _ in }
            ),
            windowSwitcherController: WindowSwitcherController(
                settings: settings,
                registry: registry,
                cgsBridge: cgsBridge,
                mode: .currentSpace
            ),
            allSpacesWindowSwitcherController: WindowSwitcherController(
                settings: settings,
                registry: registry,
                cgsBridge: cgsBridge,
                mode: .allSpaces
            ),
            hotCornerController: HotCornerController(
                settings: settings,
                actionHandler: { _ in }
            ),
            switchPresentationHelper: SpaceSwitchPresentationHelper(
                appearanceManager: appearanceManager,
                activateApp: {},
                openURL: { _ in true },
                openSystemSettingsApp: {}
            ),
            setupRequirementsPresenter: SetupRequirementsPresenter(
                appearanceManager: appearanceManager,
                switchPresentationHelper: SpaceSwitchPresentationHelper(
                    appearanceManager: appearanceManager,
                    activateApp: {},
                    openURL: { _ in true },
                    openSystemSettingsApp: {}
                )
            )
        )

        coordinator.applicationDidFinishLaunching()

        XCTAssertEqual(updateController.restoreCachedStateCallCount, 1)
        XCTAssertEqual(updateController.scheduleAutomaticCheckCallCount, 1)
    }
}

@MainActor
private final class UpdateControllerSpy: UpdateControlling {
    private(set) var restoreCachedStateCallCount = 0
    private(set) var scheduleAutomaticCheckCallCount = 0

    func restoreCachedState() {
        restoreCachedStateCallCount += 1
    }

    func scheduleAutomaticCheck() {
        scheduleAutomaticCheckCallCount += 1
    }

    func performManualCheck() {}
    func presentAvailableUpdate() {}
}

private struct FakeCGSBridge: CGSBridgeProtocol {
    func activeSpaceID() -> Int? { nil }
    func managedSnapshot() -> CGSBridge.ManagedSnapshot {
        .init(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
    }
    func managedSpaces() -> [SpaceIdentity] { [] }
    func switchByDesktopShortcut(index: Int) -> Bool { false }
    func spacesForWindow(windowID: Int) -> [Int] { [] }
}
