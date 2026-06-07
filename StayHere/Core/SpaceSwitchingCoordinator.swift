import Foundation

public final class SpaceSwitchingCoordinator {
    private let cgsBridge: any CGSBridgeProtocol
    private let stateStore: SpaceStateStore
    private let switcherService: SpaceSwitcherService
    private let orderedSpaceIDs: () -> [Int]
    private let refreshNow: () -> Void
    private let applySnapshot: (CGSBridge.ManagedSnapshot) -> Void
    private let snapshotExecutor: (DispatchWorkItem) -> Void
    private let mainExecutor: (DispatchWorkItem) -> Void
    private let scheduleAfter: (TimeInterval, DispatchWorkItem) -> Void
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private var pendingRefresh: DispatchWorkItem?

    public init(
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        stateStore: SpaceStateStore,
        switcherService: SpaceSwitcherService,
        orderedSpaceIDs: @escaping () -> [Int],
        refreshNow: @escaping () -> Void,
        applySnapshot: @escaping (CGSBridge.ManagedSnapshot) -> Void,
        snapshotQueue: DispatchQueue = DispatchQueue(label: "stayhere.snapshot", qos: .userInitiated),
        mainExecutor: @escaping (DispatchWorkItem) -> Void = { task in
            DispatchQueue.main.async(execute: task)
        },
        scheduleAfter: @escaping (TimeInterval, DispatchWorkItem) -> Void = { interval, task in
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: task)
        },
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8
    ) {
        self.cgsBridge = cgsBridge
        self.stateStore = stateStore
        self.switcherService = switcherService
        self.orderedSpaceIDs = orderedSpaceIDs
        self.refreshNow = refreshNow
        self.applySnapshot = applySnapshot
        self.snapshotExecutor = { task in
            snapshotQueue.async(execute: task)
        }
        self.mainExecutor = mainExecutor
        self.scheduleAfter = scheduleAfter
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
    }

    public func refreshSpacesAsync() {
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.cgsBridge.managedSnapshot()
            let applyTask = DispatchWorkItem { [weak self] in
                self?.applySnapshot(snapshot)
            }
            self.mainExecutor(applyTask)
        }
        snapshotExecutor(task)
    }

    public func refreshSpacesSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        let baseline = stateStore.activeSpaceID
        refreshNow()
        guard stateStore.activeSpaceID == baseline else { return }
        scheduleRefreshRetry(baseline: baseline, remainingAttempts: refreshRetryLimit)
    }

    public func switchToSpace(_ spaceID: Int) -> SpaceRegistry.SwitchResult {
        switcherService.switchToSpace(
            spaceID,
            snapshot: stateStore.currentSwitchSnapshot(),
            refreshSpaces: { [weak self] in
                guard let self else {
                    return SpaceSwitchSnapshot(activeSpaceID: nil, spaces: [], nativeOrderByDisplay: [:])
                }
                self.refreshNow()
                return self.stateStore.currentSwitchSnapshot()
            },
            scheduleRefreshSoon: { [weak self] in
                self?.refreshSpacesSoon()
            }
        )
    }

    public func switchToNextSpace() {
        switchToAdjacentSpace(offset: 1)
    }

    public func switchToPreviousSpace() {
        switchToAdjacentSpace(offset: -1)
    }

    private func switchToAdjacentSpace(offset: Int) {
        let ordered = orderedSpaceIDs()
        let target = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: stateStore.activeSpaceID, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: stateStore.activeSpaceID, orderedSpaceIDs: ordered)
        guard let target else {
            Logger.shared.info("switch-space cycle skipped=empty")
            return
        }
        _ = switchToSpace(target)
    }

    private func scheduleRefreshRetry(baseline: Int?, remainingAttempts: Int) {
        pendingRefresh?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshNow()
            self.pendingRefresh = nil
            guard self.stateStore.activeSpaceID == baseline, remainingAttempts > 1 else { return }
            self.scheduleRefreshRetry(baseline: baseline, remainingAttempts: remainingAttempts - 1)
        }
        pendingRefresh = task
        scheduleAfter(refreshRetryInterval, task)
    }
}
