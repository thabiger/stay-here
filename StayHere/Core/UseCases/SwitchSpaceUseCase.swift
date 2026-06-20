import Foundation

public final class SwitchSpaceUseCase {
    private let coordinator: SpaceSwitchingCoordinator

    public init(
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        repository: SpaceRepository,
        switcherService: SpaceSwitcherService? = nil,
        refreshUseCase: RefreshSpacesUseCase,
        logger: any Logging
    ) {
        self.coordinator = SpaceSwitchingCoordinator(
            cgsBridge: cgsBridge,
            repository: repository,
            switcherService: switcherService ?? SpaceSwitcherService(cgsBridge: cgsBridge, logger: logger),
            refreshSpaces: { [weak refreshUseCase] in
                refreshUseCase?.execute()
            },
            scheduleRefreshSoon: { [weak refreshUseCase] in
                refreshUseCase?.executeSoon()
            },
            logger: logger
        )
    }

    public func execute(_ spaceID: Int) -> SpaceSwitchResult {
        coordinator.switchToSpace(spaceID)
    }

    public func next() {
        coordinator.switchToNextSpace()
    }

    public func previous() {
        coordinator.switchToPreviousSpace()
    }
}
