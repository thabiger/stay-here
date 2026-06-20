import XCTest
import Core
@testable import StayHereApp

@MainActor
final class EventOrchestrationCoordinatorTests: XCTestCase {
    func testHandleIncomingURLForwardsToSwitcherCoordinator() {
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: AppEventTapProxySpy()
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
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: AppEventTapProxySpy()
        )
        let urls = [
            URL(string: "stayhere://space-switcher/open")!,
            URL(string: "stayhere://window-switcher/close")!
        ]

        urls.forEach(coordinator.handleIncomingURL)

        XCTAssertEqual(switcherCoordinator.receivedURLs, urls)
    }

    func testStartRegistersActivationClientAndStartsSwitcherCoordinator() {
        let activationController = ActivationControllingSpy(eventTapClient: FakeEventTapClient())
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let proxy = AppEventTapProxySpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: activationController,
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: proxy
        )

        coordinator.startEventDrivenControllers()

        XCTAssertEqual(activationController.startCallCount, 1)
        XCTAssertEqual(proxy.registeredClients.count, 1)
        XCTAssertIdentical(proxy.registeredClients.first as? FakeEventTapClient, activationController.eventTapClient as? FakeEventTapClient)
        XCTAssertEqual(switcherCoordinator.startCallCount, 1)
        XCTAssertEqual(switcherCoordinator.syncControllersCallCount, 1)
    }

    func testStartWithoutActivationClientDoesNotRegisterNil() {
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let proxy = AppEventTapProxySpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: HotCornerControllingSpy(),
            activationController: ActivationControllingSpy(),
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: proxy
        )

        coordinator.startEventDrivenControllers()

        XCTAssertTrue(proxy.registeredClients.isEmpty)
    }

    func testStopRemovesAllClientsAndStopsSubordinates() {
        let activationController = ActivationControllingSpy(eventTapClient: FakeEventTapClient())
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let hotCornerController = HotCornerControllingSpy()
        let proxy = AppEventTapProxySpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: hotCornerController,
            activationController: activationController,
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: proxy
        )

        coordinator.startEventDrivenControllers()
        coordinator.stopEventDrivenControllers()

        XCTAssertTrue(proxy.registeredClients.isEmpty)
        XCTAssertTrue(proxy.didRemoveAllClients)
        XCTAssertEqual(switcherCoordinator.stopCallCount, 1)
        XCTAssertEqual(activationController.stopCallCount, 1)
        XCTAssertEqual(hotCornerController.stopCallCount, 2)
    }

    func testSyncEventDrivenControllersSyncsSwitchersAndHotCorners() {
        let switcherCoordinator = SwitcherCoordinatingSpy()
        let hotCornerController = HotCornerControllingSpy()
        let coordinator = EventOrchestrationCoordinator(
            hotCornerController: hotCornerController,
            activationController: ActivationControllingSpy(),
            switcherCoordinator: switcherCoordinator,
            eventTapProxy: AppEventTapProxySpy()
        )

        coordinator.syncEventDrivenControllers()

        XCTAssertEqual(switcherCoordinator.syncControllersCallCount, 1)
        XCTAssertEqual(hotCornerController.startCallCount, 0)
        XCTAssertEqual(hotCornerController.stopCallCount, 1)

        hotCornerController.hasAssignedCornersReturnValue = true
        coordinator.syncEventDrivenControllers()

        XCTAssertEqual(switcherCoordinator.syncControllersCallCount, 2)
        XCTAssertEqual(hotCornerController.startCallCount, 1)
    }
}

@MainActor
private final class SwitcherCoordinatingSpy: SwitcherCoordinating {
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
    let eventTapClient: (any CGEventTapClient)?

    init(eventTapClient: (any CGEventTapClient)? = nil) {
        self.eventTapClient = eventTapClient
    }

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
}

private final class FakeEventTapClient: CGEventTapClient {
    var hasActiveSession: Bool = false
    var handlesKeyboardEvents: Bool = false
    var handlesMouseEvents: Bool = false

    func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        Unmanaged.passUnretained(event)
    }
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
