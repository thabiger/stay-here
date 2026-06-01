import Foundation
import Core

public final class ActivationController {
    private let windowIndex = WindowIndex()
    private let policy = ActivationPolicy()
    private let executor = ActivationExecutor()
    private var interceptor: DockClickInterceptor?
    private let currentSpaceID: () -> Int?
    private let activeSpaceIDs: () -> Set<Int>

    public init(currentSpaceID: @escaping () -> Int?, activeSpaceIDs: @escaping () -> Set<Int>) {
        self.currentSpaceID = currentSpaceID
        self.activeSpaceIDs = activeSpaceIDs
    }

    public func start() {
        let interceptor = DockClickInterceptor { [weak self] bundleID, optionHeld in
            self?.handleDockClick(bundleID: bundleID, optionHeld: optionHeld)
        }
        self.interceptor = interceptor
        interceptor.start()
    }

    public func stop() {
        interceptor?.stop()
        interceptor = nil
    }

    private func handleDockClick(bundleID: String, optionHeld: Bool) {
        let targetSpace = currentSpaceID()
        let activeSpaces = activeSpaceIDs()
        let summary = windowIndex.summarize(bundleID: bundleID, activeSpaceIDs: activeSpaces, targetSpaceID: targetSpace)
        let context = ActivationContext(bundleID: bundleID, activeSpaceIDs: activeSpaces, targetSpaceID: targetSpace, appWindowSummary: summary)
        let decision = policy.decide(context)

        Logger.shared.info(
            "activation bundle=\(bundleID) mode=\(ActivationSettings.shared.mode.rawValue) option=\(optionHeld) target=\(targetSpace ?? -1) active=\(activeSpaces.sorted()) on_current=\(summary?.hasWindowOnCurrentSpace ?? false) on_target=\(summary?.hasWindowOnTargetSpace ?? false) total=\(summary?.totalWindowCount ?? 0) decision=\(decision.rawValue)"
        )

        executor.execute(decision: decision, context: context)
    }
}
