import Foundation
import Core

@MainActor
final class WindowSwitchUseCase {
    struct Dependencies {
        let cgsBridge: any CGSBridgeProtocol
        let listProvider: WindowListProvider
        let switchSpace: SwitchSpaceUseCase
        let refreshSpaces: RefreshSpacesUseCase
        let focusService: WindowFocusService
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func execute(entry: WindowEntry, previousSpaceID: Int?) async {
        let windowSpaceIDs = dependencies.cgsBridge.spacesForWindow(windowID: entry.windowID)
        let currentSpaceID = dependencies.listProvider.currentContext()?.spaceID
        let targetSpaceID = windowSpaceIDs.first(where: { $0 != currentSpaceID })
            ?? windowSpaceIDs.first
        let needsSpaceSwitch = targetSpaceID != nil && targetSpaceID != currentSpaceID

        if needsSpaceSwitch, let targetSpaceID {
            _ = await dependencies.switchSpace.execute(targetSpaceID)
        }

        focusWindowAndRefresh(entry: entry, previousSpaceID: previousSpaceID)
    }

    private func focusWindowAndRefresh(entry: WindowEntry, previousSpaceID: Int?) {
        dependencies.focusService.focusWindow(entry: entry)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let currentContext = self.dependencies.listProvider.currentContext()
            if currentContext?.spaceID != previousSpaceID {
                self.dependencies.refreshSpaces.execute()
            }
        }
    }
}
