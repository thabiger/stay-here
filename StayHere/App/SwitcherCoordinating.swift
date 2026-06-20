import Foundation

@MainActor
protocol SwitcherCoordinating: AnyObject {
    func start()
    func stop()
    func syncControllers()
    func handleIncomingURL(_ url: URL)
}

extension SwitcherCoordinator: SwitcherCoordinating {}
