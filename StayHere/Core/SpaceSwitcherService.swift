import Foundation

public struct SpaceSwitchSnapshot {
    public let activeSpaceID: Int?
    public let spaces: [SpaceIdentity]
    public let nativeOrderByDisplay: [String: [Int]]

    public init(
        activeSpaceID: Int?,
        spaces: [SpaceIdentity],
        nativeOrderByDisplay: [String: [Int]]
    ) {
        self.activeSpaceID = activeSpaceID
        self.spaces = spaces
        self.nativeOrderByDisplay = nativeOrderByDisplay
    }
}

public final class SpaceSwitcherService {
    private let cgsBridge: any CGSBridgeProtocol
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private let waitForRefresh: (TimeInterval) -> Void
    private let logger: any Logging

    public init(
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8,
        waitForRefresh: @escaping (TimeInterval) -> Void = { interval in
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        },
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
        self.waitForRefresh = waitForRefresh
        self.logger = logger
    }

    public func switchToSpace(
        _ spaceID: Int,
        snapshot: SpaceSwitchSnapshot,
        refreshSpaces: () -> SpaceSwitchSnapshot,
        scheduleRefreshSoon: () -> Void
    ) -> SpaceSwitchResult {
        if snapshot.activeSpaceID == spaceID {
            logger.info("switch-space skipped=already-active")
            return .alreadyActive
        }

        guard snapshot.spaces.first(where: { $0.id == spaceID })?.kind == .desktop else {
            logger.error("switch-space failed=unsupported-space-kind")
            return .unsupportedSpaceKind
        }

        let liveSnapshot = cgsBridge.managedSnapshot()
        guard let display = snapshot.spaces.first(where: { $0.id == spaceID })?.display
            ?? liveSnapshot.spaces.first(where: { $0.id == spaceID })?.display,
              let nativeOrder = snapshot.nativeOrderByDisplay[display] ?? liveSnapshot.orderedIDsByDisplay[display],
              let shortcutIndex = nativeOrder.firstIndex(of: spaceID).map({ $0 + 1 }) else {
            logger.error("switch-space failed=unknown-space")
            return .unknownSpace
        }

        guard shortcutIndex <= 9 else {
            logger.error("switch-space failed=desktop-no-shortcut")
            return .unsupportedDesktop(index: shortcutIndex)
        }

        guard cgsBridge.switchByDesktopShortcut(index: shortcutIndex) else {
            logger.error("switch-space failed=event-post")
            return .eventPostFailed(index: shortcutIndex)
        }

        logger.info("switch-space posted")

        let refreshed = verifySwitchResult(expectedSpaceID: spaceID, refreshSpaces: refreshSpaces)
        logger.info("switch-space result matched=\(refreshed.activeSpaceID == spaceID)")
        guard refreshed.activeSpaceID == spaceID else {
            logger.error("switch-space failed=shortcut-posted-but-unmatched")
            scheduleRefreshSoon()
            return .switchUnmatched(
                index: shortcutIndex,
                expectedSpaceID: spaceID,
                actualSpaceID: refreshed.activeSpaceID
            )
        }

        scheduleRefreshSoon()
        return .switched
    }

    private func verifySwitchResult(
        expectedSpaceID: Int,
        refreshSpaces: () -> SpaceSwitchSnapshot
    ) -> SpaceSwitchSnapshot {
        let initial = refreshSpaces()
        if initial.activeSpaceID == expectedSpaceID {
            return initial
        }

        var latest = initial
        for _ in 0..<refreshRetryLimit {
            waitForRefresh(refreshRetryInterval)
            latest = refreshSpaces()
            if latest.activeSpaceID == expectedSpaceID {
                return latest
            }
        }

        return latest
    }
}
