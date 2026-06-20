import Foundation

public final class RefreshSpacesUseCase {
    private let repository: SpaceRepository
    private let snapshotExecutor: (DispatchWorkItem) -> Void
    private let mainExecutor: (DispatchWorkItem) -> Void
    private let scheduleAfter: (TimeInterval, DispatchWorkItem) -> Void
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private let logger: any Logging
    private var pendingRefresh: DispatchWorkItem?

    public init(
        repository: SpaceRepository,
        snapshotQueue: DispatchQueue = DispatchQueue(label: "stayhere.snapshot", qos: .userInitiated),
        mainExecutor: @escaping (DispatchWorkItem) -> Void = { task in
            DispatchQueue.main.async(execute: task)
        },
        scheduleAfter: @escaping (TimeInterval, DispatchWorkItem) -> Void = { interval, task in
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: task)
        },
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8,
        logger: any Logging
    ) {
        self.repository = repository
        self.snapshotExecutor = { task in
            snapshotQueue.async(execute: task)
        }
        self.mainExecutor = mainExecutor
        self.scheduleAfter = scheduleAfter
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
        self.logger = logger
    }

    public func execute() {
        repository.applyManagedSnapshot(repository.cgsBridge.managedSnapshot())
    }

    public func executeAsync() {
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.repository.cgsBridge.managedSnapshot()
            let applyTask = DispatchWorkItem { [weak self] in
                self?.repository.applyManagedSnapshot(snapshot)
            }
            self.mainExecutor(applyTask)
        }
        snapshotExecutor(task)
    }

    public func executeSoon() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        let baseline = repository.activeSpaceID
        execute()
        guard repository.activeSpaceID == baseline else { return }
        scheduleRefreshRetry(baseline: baseline, remainingAttempts: refreshRetryLimit)
    }

    private func scheduleRefreshRetry(baseline: Int?, remainingAttempts: Int) {
        pendingRefresh?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.execute()
            self.pendingRefresh = nil
            guard self.repository.activeSpaceID == baseline, remainingAttempts > 1 else { return }
            self.scheduleRefreshRetry(baseline: baseline, remainingAttempts: remainingAttempts - 1)
        }
        pendingRefresh = task
        scheduleAfter(refreshRetryInterval, task)
    }
}
