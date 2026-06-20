import XCTest
import Core

final class SpaceSwitcherServiceTests: XCTestCase {
    func testSwitchToSpaceUsesDesktopShortcutIndexFromDisplayOrder() {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            )
        )
        var postedIndex: Int?
        bridge.switchByDesktopShortcutHandler = { index in
            postedIndex = index
            bridge.activeSpaceIDValue = 102
            return true
        }

        let service = SpaceSwitcherService(
            cgsBridge: bridge,
            refreshRetryLimit: 0,
            waitForRefresh: { _ in },
            logger: NoOpLogger()
        )
        var refreshedState = SpaceSwitchSnapshot(
            activeSpaceID: 101,
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
            ],
            nativeOrderByDisplay: ["display-a": [101, 102]]
        )

        let result = service.switchToSpace(
            102,
            snapshot: refreshedState,
            refreshSpaces: {
                refreshedState = SpaceSwitchSnapshot(
                    activeSpaceID: bridge.activeSpaceIDValue,
                    spaces: refreshedState.spaces,
                    nativeOrderByDisplay: refreshedState.nativeOrderByDisplay
                )
                return refreshedState
            },
            scheduleRefreshSoon: {}
        )

        XCTAssertEqual(result, .switched)
        XCTAssertEqual(postedIndex, 2)
    }

    func testSwitchToSpaceReturnsUnmatchedWhenActiveSpaceNeverChanges() {
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 101,
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 101],
                orderedIDsByDisplay: ["display-a": [101, 102]]
            ),
            switchByDesktopShortcutHandler: { _ in true }
        )
        let service = SpaceSwitcherService(
            cgsBridge: bridge,
            refreshRetryLimit: 1,
            waitForRefresh: { _ in },
            logger: NoOpLogger()
        )
        let snapshot = SpaceSwitchSnapshot(
            activeSpaceID: 101,
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
            ],
            nativeOrderByDisplay: ["display-a": [101, 102]]
        )
        var refreshSoonCalled = false

        let result = service.switchToSpace(
            102,
            snapshot: snapshot,
            refreshSpaces: { snapshot },
            scheduleRefreshSoon: { refreshSoonCalled = true }
        )

        XCTAssertEqual(
            result,
            .switchUnmatched(index: 2, expectedSpaceID: 102, actualSpaceID: 101)
        )
        XCTAssertTrue(refreshSoonCalled)
    }
}
