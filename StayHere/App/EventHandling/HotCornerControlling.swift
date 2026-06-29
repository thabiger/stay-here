import Foundation

@MainActor
protocol HotCornerControlling: AnyObject {
    func start()
    func stop()
    func hasAssignedCorners() -> Bool
}

extension HotCornerController: HotCornerControlling {}
