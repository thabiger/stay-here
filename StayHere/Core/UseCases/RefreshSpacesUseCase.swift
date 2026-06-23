import Foundation

@MainActor
public final class RefreshSpacesUseCase {
    private let repository: SpaceStateManager
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private let logger: any Logging
    private var pendingRefreshTask: Task<Void, Never>?

    public init(
        repository: SpaceStateManager,
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8,
        logger: any Logging
    ) {
        self.repository = repository
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
        self.logger = logger
    }

    public func execute() {
        let snapshot = repository.cgsBridge.managedSnapshot()
        repository.applyManagedSnapshot(snapshot)
    }

    public func executeAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let snapshot = await MainActor.run {
                self.repository.cgsBridge.managedSnapshot()
            }
            await MainActor.run {
                self.repository.applyManagedSnapshot(snapshot)
            }
        }
    }

    public func executeSoon() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        let baseline = repository.activeSpaceID

        execute()

        let currentBaseline = repository.activeSpaceID
        guard currentBaseline == baseline else { return }

        scheduleRefreshRetry(baseline: baseline, remainingAttempts: refreshRetryLimit)
    }

    private func scheduleRefreshRetry(baseline: Int?, remainingAttempts: Int) {
        pendingRefreshTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<remainingAttempts {
                try? await Task.sleep(nanoseconds: UInt64(self.refreshRetryInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.execute()
                }

                guard !Task.isCancelled else { return }

                let done: Bool = await MainActor.run {
                    let current = self.repository.activeSpaceID
                    return current != baseline || current == nil
                }
                if done { return }
            }
        }
        pendingRefreshTask = task
    }
}
