import AppKit
import Core
import Activation

@MainActor
final class EventOrchestrationCoordinator {
    private let hotCornerController: any HotCornerControlling
    private let activationController: any ActivationControlling
    private let switcherCoordinator: any SwitcherCoordinating

    init(
        hotCornerController: any HotCornerControlling,
        activationController: any ActivationControlling,
        switcherCoordinator: any SwitcherCoordinating
    ) {
        self.hotCornerController = hotCornerController
        self.activationController = activationController
        self.switcherCoordinator = switcherCoordinator
    }

    func startEventDrivenControllers() {
        activationController.start()
        syncEventDrivenControllers()
    }

    func stopEventDrivenControllers() {
        hotCornerController.stop()
        switcherCoordinator.stop()
        activationController.stop()
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
