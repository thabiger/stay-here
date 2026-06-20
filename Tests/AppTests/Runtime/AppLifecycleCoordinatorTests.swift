import XCTest
import Core
@testable import StayHereApp

final class AppLifecycleCoordinatorTests: XCTestCase {
    func testSatisfiedSetupStartsControllersWithoutWarning() {
        let coordinator = AppLifecycleCoordinator(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository()),
            applyAppearance: {},
            setupStatusProvider: {
                AppSetupStatusSnapshot(isSatisfied: true, missingDescriptionsCount: 0)
            },
            setActivationPolicy: { _ in },
            logger: NoOpLogger()
        )
        var startedControllers = false
        var presentedWarning = false

        coordinator.applicationDidFinishLaunching(
            isSettingsOpen: { false },
            refreshSpacesSoon: {},
            refreshSpacesAsync: {},
            rebuildSpaceItems: {},
            startEventDrivenControllers: { startedControllers = true },
            presentSetupRequirementsWarning: { presentedWarning = true }
        )

        XCTAssertTrue(startedControllers)
        XCTAssertFalse(presentedWarning)
    }

    func testUnsatisfiedSetupPresentsWarningWithoutStartingControllers() {
        let coordinator = AppLifecycleCoordinator(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository()),
            applyAppearance: {},
            setupStatusProvider: {
                AppSetupStatusSnapshot(isSatisfied: false, missingDescriptionsCount: 1)
            },
            setActivationPolicy: { _ in },
            logger: NoOpLogger()
        )
        var startedControllers = false
        var presentedWarning = false

        coordinator.applicationDidFinishLaunching(
            isSettingsOpen: { false },
            refreshSpacesSoon: {},
            refreshSpacesAsync: {},
            rebuildSpaceItems: {},
            startEventDrivenControllers: { startedControllers = true },
            presentSetupRequirementsWarning: { presentedWarning = true }
        )

        XCTAssertFalse(startedControllers)
        XCTAssertTrue(presentedWarning)
    }

    func testHandleActiveSpaceChangedSkipsRefreshWhileSettingsAreOpen() {
        let coordinator = AppLifecycleCoordinator(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository()),
            applyAppearance: {},
            setActivationPolicy: { _ in },
            logger: NoOpLogger()
        )
        var refreshCount = 0

        coordinator.handleActiveSpaceChanged(isSettingsOpen: true) {
            refreshCount += 1
        }
        coordinator.handleActiveSpaceChanged(isSettingsOpen: false) {
            refreshCount += 1
        }

        XCTAssertEqual(refreshCount, 1)
    }
}
