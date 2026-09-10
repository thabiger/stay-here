import Foundation
import AppKit
import Core
import OSLog

public final class ActivationExecutor {
    private let showSingleWindowHint: (String) -> Void
    private let switchToSpace: (Int) -> Void
    private let currentSpaceID: () -> Int?
    private let appActivator: AppActivator
    private let shortcutPoster: ShortcutPoster

    private static let activationLog = Logger(
        subsystem: "com.stayhere.StayHere",
        category: "activation-executor"
    )

    private final class CancellationFlag {
        private let _lock = NSLock()
        private var _cancelled = false

        var isCancelled: Bool {
            _lock.lock()
            defer { _lock.unlock() }
            return _cancelled
        }

        func cancel() {
            _lock.lock()
            defer { _lock.unlock() }
            _cancelled = true
        }
    }

    private var pendingWaitFlag: CancellationFlag?
    private var pendingRetryTask: Task<Void, Never>?

    /// Test seam — fires on **confirmed space match**, or as an
    /// **explicit degraded fallback** after a confirmed timeout (final
    /// verification read still unmatched). A cancelled chain increments
    /// nothing.
    internal var testThenCallCount: Int = 0

    /// Test seam — counts only confirmed timeouts (deadline passed +
    /// verification read unmatched). A cancelled chain increments
    /// nothing.
    internal var testTimeoutCallCount: Int = 0

    public init(
        showSingleWindowHint: @escaping (String) -> Void = { _ in },
        switchToSpace: @escaping (Int) -> Void = { _ in },
        currentSpaceID: @escaping () -> Int? = { nil },
        appActivator: AppActivator = AppActivator(),
        shortcutPoster: ShortcutPoster = ShortcutPoster()
    ) {
        self.showSingleWindowHint = showSingleWindowHint
        self.switchToSpace = switchToSpace
        self.currentSpaceID = currentSpaceID
        self.appActivator = appActivator
        self.shortcutPoster = shortcutPoster
    }

    public func execute(decision: ActivationDecision, context: ActivationContext) -> Bool {
        switch decision {
        case .launch:
            appActivator.launch(bundleID: context.bundleID)
            return true
        case .focusCurrentSpace:
            appActivator.focus(bundleID: context.bundleID)
            return true
        case .createNewWindow:
            appActivator.focus(bundleID: context.bundleID)
            shortcutPoster.sendNewWindowShortcut(toBundleID: context.bundleID)
            return true
        case .singleWindowHint:
            showSingleWindowHint(singleWindowHintMessage(bundleID: context.bundleID))
            return true
        case .switchToSingleWindowSpace:
            return switchToAppSpace(context: context)
        case .consumeOnly:
            return true
        case .passthrough:
            return false
        }
    }

    public func switchToAppSpace(context: ActivationContext) -> Bool {
        guard let spaceID = context.singleWindowSpaceID ?? preferredSpaceID(for: context.appWindowSummary) else {
            return false
        }
        cancelAllPendingWork()
        switchToSpace(spaceID)

        waitForActiveSpace(spaceID, timeout: 1.0) { [weak self] in
            guard let self else { return }
            self.appActivator.focus(bundleID: context.bundleID)
            self.scheduleRetryFocus(bundleID: context.bundleID)
        }

        return true
    }

    /// Cancels any in-flight `waitForActiveSpace` polling chain and the
    /// 0.12s retry `focus` callback. Idempotent. Internal so it can be
    /// exercised from unit tests; production callers reach it via
    /// `switchToAppSpace`.
    internal func cancelAllPendingWork() {
        pendingWaitFlag?.cancel()
        pendingWaitFlag = nil
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
    }

    private func preferredSpaceID(for summary: AppWindowSummary?) -> Int? {
        summary?.allWindows.compactMap(\.spaceIDs.first).first
    }

    private func singleWindowHintMessage(bundleID: String) -> String {
        let appName = appActivator.displayName(forBundleID: bundleID) ?? bundleID
        return "\(appName) was clicked. It is configured as a single-window app. Use Option+Click to switch to the space where it is running."
    }

    private func scheduleRetryFocus(bundleID: String) {
        pendingRetryTask?.cancel()
        pendingRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
            guard let self, !Task.isCancelled else { return }
            if !self.appActivator.isAppActive(bundleID: bundleID) {
                self.appActivator.focus(bundleID: bundleID)
            }
        }
    }

    internal func waitForActiveSpace(_ spaceID: Int, timeout: TimeInterval, then: @escaping @Sendable () -> Void) {
        let flag = CancellationFlag()
        pendingWaitFlag = flag
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            guard !flag.isCancelled else { return }
            // Confirmed success — checked first so a switch that lands at/after
            // the deadline is still success, never timeout.
            if currentSpaceID() == spaceID {
                guard !flag.isCancelled else { return }
                testThenCallCount += 1
                then()
                return
            }
            guard Date() < deadline else {
                // Deadline elapsed with no match. One final verification read:
                // give a late-arriving switch a last chance to land before we
                // declare the outcome undetermined. nil is *unknown* here, so it
                // falls through to the timeout path — nil never fires then() early.
                if currentSpaceID() == spaceID {
                    guard !flag.isCancelled else { return }
                    testThenCallCount += 1
                    then()
                    return
                }
                guard !flag.isCancelled else { return }
                testTimeoutCallCount += 1
                Self.activationLog.error(
                    "Space switch to \(spaceID, privacy: .public) did not complete within \(timeout, privacy: .public)s; activating app on the current space as degraded fallback"
                )
                testThenCallCount += 1
                then()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }
}
