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

public actor SpaceSwitcherService {
    private let cgsBridge: any CGSBridgeProtocol
    private let refreshRetryInterval: TimeInterval
    private let refreshRetryLimit: Int
    private let logger: any Logging

    public init(
        cgsBridge: any CGSBridgeProtocol,
        refreshRetryInterval: TimeInterval = 0.05,
        refreshRetryLimit: Int = 8,
        logger: any Logging
    ) {
        self.cgsBridge = cgsBridge
        self.refreshRetryInterval = refreshRetryInterval
        self.refreshRetryLimit = refreshRetryLimit
        self.logger = logger
    }

    public func switchToSpace(
        _ spaceID: Int,
        snapshot: SpaceSwitchSnapshot,
        refreshSpaces: () async -> SpaceSwitchSnapshot,
        scheduleRefreshSoon: () -> Void
    ) async -> SpaceSwitchResult {
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

        let refreshed = await verifySwitchResult(expectedSpaceID: spaceID, refreshSpaces: refreshSpaces)
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
        refreshSpaces: () async -> SpaceSwitchSnapshot
    ) async -> SpaceSwitchSnapshot {
        let initial = await refreshSpaces()
        if initial.activeSpaceID == expectedSpaceID {
            return initial
        }

        var latest = initial
        for _ in 0..<refreshRetryLimit {
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshRetryInterval * 1_000_000_000))
            } catch {
                return latest
            }
            latest = await refreshSpaces()
            if latest.activeSpaceID == expectedSpaceID {
                return latest
            }
        }

        return latest
    }
}
