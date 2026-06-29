import Foundation

@MainActor
protocol SwitcherDirecting: AnyObject {
    func start()
    func stop()
    func syncControllers()
    func handleIncomingURL(_ url: URL)
}

extension SwitcherDirector: SwitcherDirecting {}
