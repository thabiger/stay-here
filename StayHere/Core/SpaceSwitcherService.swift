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

    public init(
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8,
        waitForRefresh: @escaping (TimeInterval) -> Void = { interval in
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
    ) {
        self.cgsBridge = cgsBridge
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
        self.waitForRefresh = waitForRefresh
    }

    public func switchToSpace(
        _ spaceID: Int,
        snapshot: SpaceSwitchSnapshot,
        refreshSpaces: () -> SpaceSwitchSnapshot,
        scheduleRefreshSoon: () -> Void
    ) -> SpaceRegistry.SwitchResult {
        if snapshot.activeSpaceID == spaceID {
            Logger.shared.info("switch-space skipped=already-active")
            return .alreadyActive
        }

        guard snapshot.spaces.first(where: { $0.id == spaceID })?.kind == .desktop else {
            Logger.shared.error("switch-space failed=unsupported-space-kind")
            return .unsupportedSpaceKind
        }

        let liveSnapshot = cgsBridge.managedSnapshot()
        guard let display = snapshot.spaces.first(where: { $0.id == spaceID })?.display
            ?? liveSnapshot.spaces.first(where: { $0.id == spaceID })?.display,
              let nativeOrder = snapshot.nativeOrderByDisplay[display] ?? liveSnapshot.orderedIDsByDisplay[display],
              let shortcutIndex = nativeOrder.firstIndex(of: spaceID).map({ $0 + 1 }) else {
            Logger.shared.error("switch-space failed=unknown-space")
            return .unknownSpace
        }

        guard shortcutIndex <= 9 else {
            Logger.shared.error("switch-space failed=desktop-no-shortcut")
            return .unsupportedDesktop(index: shortcutIndex)
        }

        guard cgsBridge.switchByDesktopShortcut(index: shortcutIndex) else {
            Logger.shared.error("switch-space failed=event-post")
            return .eventPostFailed(index: shortcutIndex)
        }

        Logger.shared.info("switch-space posted")

        let refreshed = verifySwitchResult(expectedSpaceID: spaceID, refreshSpaces: refreshSpaces)
        Logger.shared.info("switch-space result matched=\(refreshed.activeSpaceID == spaceID)")
        guard refreshed.activeSpaceID == spaceID else {
            Logger.shared.error("switch-space failed=shortcut-posted-but-unmatched")
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
