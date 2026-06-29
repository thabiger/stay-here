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

    /// Takes an immediate snapshot of the current CGS space state
    /// and applies it to the repository. Runs synchronously on the calling actor.
    public func refreshNow() {
        let snapshot = repository.cgsBridge.managedSnapshot()
        repository.applyManagedSnapshot(snapshot)
    }

    /// Asynchronously takes a snapshot and applies it, without blocking the caller.
    /// Uses a detached Task to avoid blocking the main actor.
    public func refreshAsync() {
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

    /// Immediately refreshes the repository snapshot, then polls until the
    /// active space ID changes or the retry limit is reached.
    /// Cancels any previous pending retry loop.
    public func refreshWithRetry() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        let baseline = repository.activeSpaceID

        refreshNow()

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
                    self.refreshNow()
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
