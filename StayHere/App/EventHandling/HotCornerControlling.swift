import Foundation
import Core

@MainActor
protocol HotCornerControlling: AnyObject {
    func start()
    func stop()
    func hasAssignedCorners() -> Bool
}

extension HotCornerController: HotCornerControlling {}

@MainActor
protocol HotCornerActionHandling: AnyObject {
    func handleHotCornerAction(_ action: HotCornerAction)
}

@MainActor
final class ClosureHotCornerActionHandler: HotCornerActionHandling {
    private let handler: (HotCornerAction) -> Void

    init(_ handler: @escaping (HotCornerAction) -> Void) {
        self.handler = handler
    }

    func handleHotCornerAction(_ action: HotCornerAction) {
        handler(action)
    }
}

@MainActor
final class HotCornerSwitcherDispatcher: HotCornerActionHandling {
    private let spaceSwitcher: any SwitcherControlling
    private let windowSwitcher: any SwitcherControlling
    private let allSpacesWindowSwitcher: any SwitcherControlling

    init(
        spaceSwitcher: any SwitcherControlling,
        windowSwitcher: any SwitcherControlling,
        allSpacesWindowSwitcher: any SwitcherControlling
    ) {
        self.spaceSwitcher = spaceSwitcher
        self.windowSwitcher = windowSwitcher
        self.allSpacesWindowSwitcher = allSpacesWindowSwitcher
    }

    func handleHotCornerAction(_ action: HotCornerAction) {
        switch action {
        case .none:
            break
        case .spaceSwitcher:
            spaceSwitcher.openSwitcher()
        case .windowSwitcher:
            windowSwitcher.openSwitcher()
        case .allSpacesWindowSwitcher:
            allSpacesWindowSwitcher.openSwitcher()
        }
    }
}
