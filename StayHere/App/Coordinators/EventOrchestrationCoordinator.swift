import AppKit
import Core
import Activation

@MainActor
final class EventOrchestrationCoordinator {
    private let hotCornerController: any HotCornerControlling
    private let activationController: any ActivationControlling
    private let switcherCoordinator: any SwitcherCoordinating
    private let eventTapProxy: any EventTapProxying

    init(
        hotCornerController: any HotCornerControlling,
        activationController: any ActivationControlling,
        switcherCoordinator: any SwitcherCoordinating,
        eventTapProxy: any EventTapProxying = AppEventTapProxy()
    ) {
        self.hotCornerController = hotCornerController
        self.activationController = activationController
        self.switcherCoordinator = switcherCoordinator
        self.eventTapProxy = eventTapProxy
    }

    func startEventDrivenControllers() {
        activationController.start()
        if let client = activationController.eventTapClient {
            eventTapProxy.register(client)
        }
        switcherCoordinator.start()
        syncEventDrivenControllers()
    }

    func stopEventDrivenControllers() {
        eventTapProxy.removeAllClients()
        switcherCoordinator.stop()
        activationController.stop()
        hotCornerController.stop()
    }

    func syncEventDrivenControllers() {
        switcherCoordinator.syncControllers()

        if hotCornerController.hasAssignedCorners() {
            hotCornerController.start()
        } else {
            hotCornerController.stop()
        }
    }

    func handleIncomingURL(_ url: URL) {
        switcherCoordinator.handleIncomingURL(url)
    }
}
