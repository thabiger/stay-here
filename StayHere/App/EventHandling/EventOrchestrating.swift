import Foundation

@MainActor
protocol EventOrchestrating: AnyObject {
    func startEventDrivenControllers()
    func stopEventDrivenControllers()
    func syncEventDrivenControllers()
    func handleIncomingURL(_ url: URL)
}

extension EventOrchestrationCoordinator: EventOrchestrating {}
