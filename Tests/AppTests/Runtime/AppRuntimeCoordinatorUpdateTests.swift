import XCTest
import Core
import Activation
@testable import StayHereApp

@MainActor
final class AppRuntimeCoordinatorUpdateTests: XCTestCase {
    func testLaunchRestoresCachedStateAndSchedulesAutomaticCheck() {
        let settings = UserDefaultsSettingsRepository()
        let cgsBridge = FakeCGSBridge()
        let appearanceManager = AppearanceManager(settings: settings)

        let logger: any Logging = NoOpLogger()
        let lifecycleCoordinator = AppLifecycleCoordinator(
            appearanceManager: appearanceManager,
            applyAppearance: {},
            setupStatusProvider: {
                AppSetupStatusSnapshot(isSatisfied: true, missingDescriptionsCount: 0)
            },
            setActivationPolicy: { _ in },
            logger: logger
        )

        let services = CompositionServices(
            settings: settings,
            cgsBridge: cgsBridge,
            lifecycleCoordinator: lifecycleCoordinator,
            logger: logger
        )

        let aboutWindowManager = AboutWindowManager(appearanceManager: services.appearanceManager)
        let updateWindowManager = UpdateWindowManager(appearanceManager: services.appearanceManager)

        let updateController = UpdateControllerSpy()
        let coordinator = AppRuntimeCoordinator(
            services: services,
            aboutWindowManager: aboutWindowManager,
            updateWindowManager: updateWindowManager
        )
        coordinator.setUpdateController(updateController)

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
