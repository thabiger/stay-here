import Foundation
import AppKit
import Core

public final class ActivationExecutor {
    private let showSingleWindowHint: (String) -> Void
    private let switchToSpace: (Int) -> Void
    private let currentSpaceID: () -> Int?
    private let appActivator: AppActivator
    private let shortcutPoster: ShortcutPoster

    /// Tracks a pending work item so a newer `switchToAppSpace` can
    /// short-circuit the old polling chain instead of running N
    /// concurrent uncancellable chains (R2/C13/M4).
    private final class CancellationFlag {
        var isCancelled = false
    }

    private var pendingWaitFlag: CancellationFlag?
    private var pendingRetryFlag: CancellationFlag?

    /// Test seam — counts how many times the `then` callback of
    /// `waitForActiveSpace` has been invoked. A chain that was
    /// cancelled should NOT increment this counter.
    internal var testThenCallCount: Int = 0

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
        // Cancel any in-flight polling chain and pending retry before
        // starting a new one. Rapid Option+clicks on Dock icons would
        // otherwise stack N uncancellable `RunLoop`-style chains.
        cancelAllPendingWork()
        switchToSpace(spaceID)
        focusAfterSpaceSwitch(bundleID: context.bundleID, spaceID: spaceID)
        return true
    }

    /// Cancels any in-flight `waitForActiveSpace` polling chain and the
    /// 0.12s retry `focus` callback. Idempotent. Internal so it can be
    /// exercised from unit tests; production callers reach it via
    /// `switchToAppSpace`.
    internal func cancelAllPendingWork() {
        pendingWaitFlag?.isCancelled = true
        pendingWaitFlag = nil
        pendingRetryFlag?.isCancelled = true
        pendingRetryFlag = nil
    }

    private func preferredSpaceID(for summary: AppWindowSummary?) -> Int? {
        summary?.allWindows.compactMap(\.spaceIDs.first).first
    }

    private func singleWindowHintMessage(bundleID: String) -> String {
        let appName = appActivator.displayName(forBundleID: bundleID) ?? bundleID
        return "\(appName) was clicked. It is configured as a single-window app. Use Option+Click to switch to the space where it is running."
    }

    private func focusAfterSpaceSwitch(bundleID: String, spaceID: Int) {
        waitForActiveSpace(spaceID, timeout: 1.0) { [weak self] in
            guard let self else { return }
            self.appActivator.focus(bundleID: bundleID)
            self.pendingRetryFlag = CancellationFlag()
            let flag = self.pendingRetryFlag
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self,
                      let flag, !flag.isCancelled,
                      !self.appActivator.isAppActive(bundleID: bundleID) else { return }
                self.appActivator.focus(bundleID: bundleID)
            }
        }
    }

    internal func waitForActiveSpace(_ spaceID: Int, timeout: TimeInterval, then: @escaping () -> Void) {
        let flag = CancellationFlag()
        pendingWaitFlag = flag
        let started = Date()

        func poll() {
            if flag.isCancelled { return }
            if currentSpaceID() == nil || currentSpaceID() == spaceID || Date().timeIntervalSince(started) >= timeout {
                testThenCallCount += 1
                then()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }
}
