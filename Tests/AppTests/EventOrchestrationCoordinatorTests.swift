import XCTest
@testable import StayHereApp

@MainActor
final class EventOrchestrationCoordinatorTests: XCTestCase {
    func testHandleIncomingURLForwardsToSwitcherCoordinator() {
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherCoordinator: switcherCoordinator
        )
        let url = URL(string: "stayhere://window-switcher/open")!

        coordinator.handleIncomingURL(url)

        XCTAssertEqual(switcherCoordinator.receivedURLs, [url])
    }

    func testHandleIncomingURLForwardsMultipleURLs() {
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherCoordinator: switcherCoordinator
        )
        let urls = [
            URL(string: "stayhere://space-switcher/open")!,
            URL(string: "stayhere://window-switcher/close")!
        ]

        urls.forEach(coordinator.handleIncomingURL)

        XCTAssertEqual(switcherCoordinator.receivedURLs, urls)
    }
}

@MainActor
private final class SwitcherCoordinatingSpy: SwitcherCoordinating {
    private(set) var receivedURLs: [URL] = []

    func start() {}
    func stop() {}
    func syncControllers() {}

    func handleIncomingURL(_ url: URL) {
        receivedURLs.append(url)
    }
}

@MainActor
private final class HotCornerControllingSpy: HotCornerControlling {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var hasAssignedCornersReturnValue = false

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func hasAssignedCorners() -> Bool { hasAssignedCornersReturnValue }
}

@MainActor
private final class ActivationControllingSpy: ActivationControlling {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
}
