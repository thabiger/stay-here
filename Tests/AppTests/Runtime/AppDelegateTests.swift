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

    func testOpenURLsAreForwardedToCoordinator() {
        let coordinator = AppCoordinatorSpy()
        let delegate = AppDelegate(appCoordinator: coordinator)
        let url = URL(string: "stayhere://window-switcher/open")!

        delegate.application(NSApplication.shared, open: [url])

        XCTAssertEqual(coordinator.receivedURLs, [url])
    }
}

@MainActor
private final class AppCoordinatorSpy: AppCoordinating {
    private(set) var launchCount = 0
    private(set) var terminateCount = 0
    private(set) var receivedURLs: [URL] = []

    func applicationDidFinishLaunching() {
        launchCount += 1
    }

    func applicationWillTerminate() {
        terminateCount += 1
    }

    func handleIncomingURL(_ url: URL) {
        receivedURLs.append(url)
    }
}
