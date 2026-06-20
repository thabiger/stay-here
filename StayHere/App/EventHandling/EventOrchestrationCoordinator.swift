import AppKit
import Core
import Activation

@MainActor
final class EventOrchestrationCoordinator {
    private let hotCornerController: any HotCornerControlling
    private let activationController: any ActivationControlling
    private let switcherDirector: any SwitcherDirecting
    private let eventTapProxy: any EventTapProxying

    init(
        hotCornerController: any HotCornerControlling,
        activationController: any ActivationControlling,
        switcherDirector: any SwitcherDirecting,
        eventTapProxy: any EventTapProxying
    ) {
        self.hotCornerController = hotCornerController
        self.activationController = activationController
        self.switcherDirector = switcherDirector
        self.eventTapProxy = eventTapProxy
    }

    func startEventDrivenControllers() {
        activationController.start()
        if let client = activationController.eventTapClient {
            eventTapProxy.register(client)
        }
        switcherDirector.start()
        syncEventDrivenControllers()
    }

    func stopEventDrivenControllers() {
        eventTapProxy.removeAllClients()
        switcherDirector.stop()
        activationController.stop()
        hotCornerController.stop()
    }

    func syncEventDrivenControllers() {
        switcherDirector.syncControllers()

        if hotCornerController.hasAssignedCorners() {
            hotCornerController.start()
        } else {
            hotCornerController.stop()
        }
    }

    func handleIncomingURL(_ url: URL) {
        switcherDirector.handleIncomingURL(url)
    }
}
