import XCTest
@testable import StayHereApp

@MainActor
final class AppDelegateTests: XCTestCase {
    func testLaunchIsForwardedToCoordinator() {
        let coordinator = AppCoordinatorSpy()
        let delegate = AppDelegate(appCoordinator: coordinator)

        delegate.applicationDidFinishLaunching(Notification(name: .init("test")))

        XCTAssertEqual(coordinator.launchCount, 1)
    }

    func testTerminationIsForwardedToCoordinator() {
        let coordinator = AppCoordinatorSpy()
        let delegate = AppDelegate(appCoordinator: coordinator)

        delegate.applicationWillTerminate(Notification(name: .init("test")))

        XCTAssertEqual(coordinator.terminateCount, 1)
    }
}

@MainActor
private final class AppCoordinatorSpy: AppCoordinating {
    private(set) var launchCount = 0
    private(set) var terminateCount = 0

    func applicationDidFinishLaunching() {
        launchCount += 1
    }

    func applicationWillTerminate() {
        terminateCount += 1
    }
}
