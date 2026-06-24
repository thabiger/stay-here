import Foundation
import Core

public final class ActivationController {
    private let windowIndex: WindowIndex
    private let policy: ActivationPolicy
    private let executor: ActivationExecutor
    private let settings: ActivationSettings
    private let logger: any Logging
    private var interceptor: DockClickInterceptor?
    private let currentSpaceID: () -> Int?
    private let activeSpaceIDs: () -> Set<Int>

    public init(
        settings: ActivationSettings,
        windowIndex: WindowIndex,
        policy: ActivationPolicy? = nil,
        currentSpaceID: @escaping () -> Int?,
        activeSpaceIDs: @escaping () -> Set<Int>,
        switchToSpace: @escaping (Int) -> Void = { _ in },
        onShowSingleWindowHint: @escaping (String) -> Void = { _ in },
        logger: any Logging
    ) {
        self.windowIndex = windowIndex
        self.policy = policy ?? ActivationPolicy(settings: settings)
        self.settings = settings
        self.logger = logger
        self.currentSpaceID = currentSpaceID
        self.activeSpaceIDs = activeSpaceIDs
        self.executor = ActivationExecutor(
            showSingleWindowHint: onShowSingleWindowHint,
            switchToSpace: switchToSpace,
            currentSpaceID: currentSpaceID
        )
    }

    public func start(using proxy: any EventTapProxying) {
        let interceptor = DockClickInterceptor(
            settings: settings,
            shouldIntercept: { [weak self] bundleID, optionHeld in
                self?.shouldInterceptDockClick(bundleID: bundleID, optionHeld: optionHeld) ?? false
            },
            handler: { [weak self] bundleID, optionHeld in
                self?.handleDockClick(bundleID: bundleID, optionHeld: optionHeld) ?? false
            },
            logger: logger
        )
        self.interceptor = interceptor
        proxy.register(interceptor)
    }

    public func stop(using proxy: any EventTapProxying) {
        if let interceptor {
            proxy.unregister(interceptor)
        }
        interceptor = nil
    }

    private func shouldInterceptDockClick(bundleID: String, optionHeld: Bool) -> Bool {
        let decision = decide(bundleID: bundleID, optionHeld: optionHeld, log: false)
        return decision != .passthrough
    }

    private func handleDockClick(bundleID: String, optionHeld: Bool) -> Bool {
        let decision = decide(bundleID: bundleID, optionHeld: optionHeld, log: true)
        guard decision != .passthrough else { return false }
        let context = makeContext(bundleID: bundleID, optionHeld: optionHeld)
        return executor.execute(decision: decision, context: context)
    }

    private func decide(bundleID: String, optionHeld: Bool, log: Bool) -> ActivationDecision {
        let context = makeContext(bundleID: bundleID, optionHeld: optionHeld)
        let decision = policy.decide(context)
        if log {
            logger.info(
                "activation decision=\(decision.rawValue) enabled=\(settings.activationDockClickInterceptionEnabled) option=\(optionHeld) target=\(context.targetSpaceID ?? -1) current_space_count=\(context.activeSpaceIDs.count) window_count=\(context.appWindowSummary?.totalWindowCount ?? 0)"
            )
        }
        return decision
    }

    private func makeContext(bundleID: String, optionHeld: Bool) -> ActivationContext {
        let targetSpace = currentSpaceID()
        let activeSpaces = activeSpaceIDs()
        let summary = windowIndex.summarize(bundleID: bundleID, activeSpaceIDs: activeSpaces, targetSpaceID: targetSpace)
        let singleWindowSpaceID = summary?.allWindows.compactMap { $0.spaceIDs.first }.first
        return ActivationContext(
            bundleID: bundleID,
            activeSpaceIDs: activeSpaces,
            targetSpaceID: targetSpace,
            appWindowSummary: summary,
            singleWindowSpaceID: singleWindowSpaceID,
            optionHeld: optionHeld
        )
    }
}
