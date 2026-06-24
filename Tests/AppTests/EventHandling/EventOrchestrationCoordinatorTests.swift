import XCTest
import Core
@testable import StayHereApp

@MainActor
final class EventOrchestrationCoordinatorTests: XCTestCase {
    func testHandleIncomingURLForwardsToSwitcherDirector() {
        let switcherDirector = SwitcherDirectingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherDirector: switcherDirector,
            eventTapProxy: AppEventTapProxySpy()
        )
        let url = URL(string: "stayhere://window-switcher/open")!

        coordinator.handleIncomingURL(url)

        XCTAssertEqual(switcherDirector.receivedURLs, [url])
    }

    func testHandleIncomingURLForwardsMultipleURLs() {
        let switcherDirector = SwitcherDirectingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherDirector: switcherDirector,
            eventTapProxy: AppEventTapProxySpy()
        )
        let urls = [
            URL(string: "stayhere://space-switcher/open")!,
            URL(string: "stayhere://window-switcher/close")!
        ]

        urls.forEach(coordinator.handleIncomingURL)

        XCTAssertEqual(switcherDirector.receivedURLs, urls)
    }

    func testStartRegistersActivationClientAndStartsSwitcherDirector() {
        let activationController = ActivationControllingSpy()
        let switcherDirector = SwitcherDirectingSpy()
        let proxy = AppEventTapProxySpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: activationController,
            switcherDirector: switcherDirector,
            eventTapProxy: proxy
        )

        coordinator.startEventDrivenControllers()

        XCTAssertEqual(activationController.startCallCount, 1)
        XCTAssertEqual(switcherDirector.startCallCount, 1)
        XCTAssertEqual(switcherDirector.syncControllersCallCount, 1)
    }

    func testStopRemovesAllClientsAndStopsSubordinates() {
        let activationController = ActivationControllingSpy()
        let switcherDirector = SwitcherDirectingSpy()
        let hotCornerController = HotCornerControllingSpy()
        let proxy = AppEventTapProxySpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: hotCornerController,
            activationController: activationController,
            switcherDirector: switcherDirector,
            eventTapProxy: proxy
        )

        coordinator.startEventDrivenControllers()
        coordinator.stopEventDrivenControllers()

        XCTAssertTrue(proxy.registeredClients.isEmpty)
        XCTAssertTrue(proxy.didRemoveAllClients)
        XCTAssertEqual(switcherDirector.stopCallCount, 1)
        XCTAssertEqual(activationController.stopCallCount, 1)
        XCTAssertEqual(hotCornerController.stopCallCount, 2)
    }

    func testSyncEventDrivenControllersSyncsSwitchersAndHotCorners() {
        let switcherDirector = SwitcherDirectingSpy()
        let hotCornerController = HotCornerControllingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: hotCornerController,
            activationController: ActivationControllingSpy(),
            switcherDirector: switcherDirector,
            eventTapProxy: AppEventTapProxySpy()
        )

        coordinator.syncEventDrivenControllers()

        XCTAssertEqual(switcherDirector.syncControllersCallCount, 1)
        XCTAssertEqual(hotCornerController.startCallCount, 0)
        XCTAssertEqual(hotCornerController.stopCallCount, 1)

        hotCornerController.hasAssignedCornersReturnValue = true
        coordinator.syncEventDrivenControllers()

        XCTAssertEqual(switcherDirector.syncControllersCallCount, 2)
        XCTAssertEqual(hotCornerController.startCallCount, 1)
    }
}

@MainActor
private final class SwitcherDirectingSpy: SwitcherDirecting {
    private(set) var receivedURLs: [URL] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var syncControllersCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func syncControllers() { syncControllersCallCount += 1 }

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

    func start(using proxy: any EventTapProxying) { startCallCount += 1 }
    func stop(using proxy: any EventTapProxying) { stopCallCount += 1 }
}

private final class AppEventTapProxySpy: EventTapProxying {
    private(set) var registeredClients: [any CGEventTapClient] = []
    private(set) var didRemoveAllClients = false

    func register(_ client: any CGEventTapClient) {
        registeredClients.append(client)
    }

    func unregister(_ client: any CGEventTapClient) {
        registeredClients.removeAll { $0 === client }
    }

    func removeAllClients() {
        registeredClients.removeAll()
        didRemoveAllClients = true
    }
}
