import Foundation

@MainActor
public final class SpaceSwitchExecutor {
    private let cgsBridge: any CGSBridgeProtocol
    private let repository: SpaceStateManager
    private let switcherService: SpaceSwitcherService
    private let refreshSpaces: @Sendable () async -> SpaceSwitchSnapshot
    private let scheduleRefreshSoon: @Sendable () -> Void
    private let logger: any Logging

    public init(
        cgsBridge: any CGSBridgeProtocol,
        repository: SpaceStateManager,
        switcherService: SpaceSwitcherService,
        refreshSpaces: @escaping @Sendable () async -> SpaceSwitchSnapshot,
        scheduleRefreshSoon: @escaping @Sendable () -> Void,
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.repository = repository
        self.switcherService = switcherService
        self.refreshSpaces = refreshSpaces
        self.scheduleRefreshSoon = scheduleRefreshSoon
        self.logger = logger
    }

    public func switchToSpace(_ spaceID: Int) async -> SpaceSwitchResult {
        await switcherService.switchToSpace(
            spaceID,
            snapshot: repository.currentSwitchSnapshot(),
            refreshSpaces: { [weak self] in
                guard let self else {
                    return SpaceSwitchSnapshot(activeSpaceID: nil, spaces: [], nativeOrderByDisplay: [:])
                }
                return await self.refreshSpaces()
            },
            scheduleRefreshSoon: { [weak self] in
                self?.scheduleRefreshSoon()
            }
        )
    }

    public func switchToNextSpace() async {
        await switchToAdjacentSpace(offset: 1)
    }

    public func switchToPreviousSpace() async {
        await switchToAdjacentSpace(offset: -1)
    }

    private func switchToAdjacentSpace(offset: Int) async {
        let ordered = repository.orderedSpaceIDs()
        let target = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: repository.activeSpaceID, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: repository.activeSpaceID, orderedSpaceIDs: ordered)
        guard let target else {
            logger.info("switch-space cycle skipped=empty")
            return
        }
        _ = await switchToSpace(target)
    }
}
