import Foundation

@MainActor
public final class RefreshSpacesUseCase {
    private let repository: any SpaceSnapshotRefreshable
    private let logger: any Logging
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private var pendingRefreshTask: Task<Void, Never>?
    private static let stableReadCount = 2

    public init(
        repository: any SpaceSnapshotRefreshable,
        logger: any Logging,
        refreshRetryInterval: TimeInterval = SpaceRefreshRetryPolicy.interval,
        refreshRetryLimit: Int = SpaceRefreshRetryPolicy.limit
    ) {
        self.repository = repository
        self.logger = logger
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
    }

    /// Takes an immediate snapshot of the current CGS space state
    /// and applies it to the repository. Runs synchronously on the calling actor.
    public func refreshNow() {
        repository.refreshSpaces()
    }

    /// Asynchronously takes a snapshot and applies it, without blocking the caller.
    /// Uses a detached Task to avoid blocking the main actor.
    public func refreshAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.repository.refreshSpaces()
            }
        }
    }

    /// Immediately refreshes the repository snapshot with a single call, cancelling
    /// any in-flight converging refresh first. There is no ambient retry loop — retry
    /// semantics live in the switch-verification path (SpaceSwitcherService.verifySwitchResult).
    public func refreshSoon() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        refreshNow()
    }

    /// Converging refresh used ONLY from the notification/switch path. Captures the
    /// PRE-refresh active space as the stale baseline, takes an immediate snapshot, then
    /// performs a bounded retry (up to `refreshRetryLimit` attempts at
    /// `refreshRetryInterval`, mirroring SpaceSwitcherService.verifySwitchResult) until the
    /// snapshot's active space differs from the baseline and has been observed identical
    /// `stableReadCount` consecutive times. Reads that still equal the stale baseline are
    /// never accepted as stable. Overlapping calls are coalesced: each call cancels and
    /// replaces the previous in-flight loop. The idle safety-net timer must keep calling
    /// the single-shot `refreshSoon()` — never this entry point.
    @discardableResult
    public func refreshSoonConverging() -> Task<Void, Never> {
        pendingRefreshTask?.cancel()
        let baseline = repository.activeSpaceID
        refreshNow()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.convergeToStableActiveSpace(baseline: baseline)
        }
        pendingRefreshTask = task
        return task
    }

    private func convergeToStableActiveSpace(baseline: Int?) async {
        guard !Task.isCancelled else { return }
        var candidate: Int?
        var consecutiveStableReads = 0
        for _ in 0..<refreshRetryLimit {
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshRetryInterval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            refreshNow()
            let current = repository.activeSpaceID
            guard current != baseline else { continue }
            if current == candidate {
                consecutiveStableReads += 1
                if consecutiveStableReads >= Self.stableReadCount {
                    return
                }
            } else {
                candidate = current
                consecutiveStableReads = 1
            }
        }
    }
}
