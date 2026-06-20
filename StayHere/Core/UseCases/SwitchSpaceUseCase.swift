import Foundation

public final class SwitchSpaceUseCase {
    private let executor: SpaceSwitchExecutor

    public init(
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        repository: SpaceStateManager,
        switcherService: SpaceSwitcherService? = nil,
        refreshUseCase: RefreshSpacesUseCase,
        logger: any Logging
    ) {
        self.executor = SpaceSwitchExecutor(
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

    public func execute(_ spaceID: Int) async -> SpaceSwitchResult {
        await executor.switchToSpace(spaceID)
    }

    public func next() async {
        await executor.switchToNextSpace()
    }

    public func previous() async {
        await executor.switchToPreviousSpace()
    }
}
