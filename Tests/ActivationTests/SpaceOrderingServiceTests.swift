import XCTest
@testable import Core

final class SpaceOrderingServiceTests: XCTestCase {
    private var service = SpaceOrderingService()

    func testDeriveStateUsesDisplayForGlobalActiveSpace() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .fullscreen)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201, 202]]
        )

        let derived = service.deriveState(
            snapshot: snapshot,
            globalActiveID: 201,
            previousActiveID: nil,
            previousSpaces: [],
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )

        XCTAssertEqual(derived.spaces.map(\.id), [201, 202])
        XCTAssertEqual(derived.activeSpaceID, 201)
        XCTAssertFalse(derived.isStaleSnapshot)
    }

    func testDeriveStateReturnsEmptyStaleStateWhenSnapshotIsEmpty() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [],
            activeByDisplay: [:],
            orderedIDsByDisplay: [:]
        )

        let derived = service.deriveState(
            snapshot: snapshot,
            globalActiveID: nil,
            previousActiveID: nil,
            previousSpaces: [],
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )

        XCTAssertEqual(derived.spaces, [])
        XCTAssertTrue(derived.isStaleSnapshot)
        XCTAssertNil(derived.activeSpaceID)
    }

    func testDeriveStateKeepsPreviousSpacesWhenSelectedDisplayHasNoSpacesButSnapshotIsNonEmpty() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        let previous = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
        ]
        let derived = service.deriveState(
            snapshot: snapshot, globalActiveID: 101,
            previousActiveID: 101, previousSpaces: previous,
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )
        XCTAssertEqual(derived.spaces, previous)
    }

    func testDeriveStateDoesNotRetainEmptyPreviousSpacesAtLaunch() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        let derived = service.deriveState(
            snapshot: snapshot, globalActiveID: 101,
            previousActiveID: nil, previousSpaces: [],
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )
        XCTAssertEqual(derived.spaces, [], "An empty previous list must never be retained")
        XCTAssertNil(derived.activeSpaceID, "activeSpaceID must not dangle outside an empty list")
        XCTAssertFalse(derived.retainedPreviousSpaces)
        XCTAssertFalse(derived.isStaleSnapshot)
    }

    func testDeriveStateCarriesForwardOrderingMetadataDuringRetention() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        let previous = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
        ]
        let derived = service.deriveState(
            snapshot: snapshot, globalActiveID: 101,
            previousActiveID: 101, previousSpaces: previous,
            previousNativeOrderByDisplay: ["display-a": [101, 102]],
            previousDesktopNumberBySpaceID: [101: 1, 102: 2],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )
        XCTAssertEqual(derived.spaces, previous)
        XCTAssertTrue(derived.retainedPreviousSpaces)
        XCTAssertEqual(derived.nativeOrderByDisplay, ["display-a": [101, 102]],
                       "Retention must carry forward the previous epoch's native order")
        XCTAssertEqual(derived.desktopNumberBySpaceID, [101: 1, 102: 2],
                       "Retention must carry forward the previous epoch's desktop numbering")
    }

    func testDeriveStateConvergesToStaleStateAfterConsecutiveAnomalyRefreshes() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        let previous = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
        ]
        var count = 0
        for _ in 0..<(SpaceStateManager.maxConsecutiveAnomalyRetentions - 1) {
            let derived = service.deriveState(
                snapshot: snapshot, globalActiveID: 101,
                previousActiveID: 101, previousSpaces: previous,
                previousNativeOrderByDisplay: ["display-a": [101, 102]],
                previousDesktopNumberBySpaceID: [101: 1, 102: 2],
                consecutiveAnomalyRetentions: count,
                maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
            )
            XCTAssertEqual(derived.spaces, previous, "Previous spaces are retained within the anomaly budget")
            XCTAssertTrue(derived.retainedPreviousSpaces)
            XCTAssertFalse(derived.isStaleSnapshot)
            count = derived.retainedPreviousSpaces ? count + 1 : 0
        }
        let converged = service.deriveState(
            snapshot: snapshot, globalActiveID: 101,
            previousActiveID: 101, previousSpaces: previous,
            previousNativeOrderByDisplay: ["display-a": [101, 102]],
            previousDesktopNumberBySpaceID: [101: 1, 102: 2],
            consecutiveAnomalyRetentions: count,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )
        XCTAssertEqual(
            converged.spaces,
            [],
            "Once the anomaly budget is exhausted the retained list is dropped and the state goes stale"
        )
        XCTAssertTrue(converged.isStaleSnapshot)
        XCTAssertFalse(converged.retainedPreviousSpaces)
    }

    func testDeriveStateClampsActiveSpaceIDIntoRetainedSpaces() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 201, display: "display-b", kind: .desktop)],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-b": [201]]
        )
        let previous = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop)
        ]
        let derived = service.deriveState(
            snapshot: snapshot, globalActiveID: 999,
            previousActiveID: 101, previousSpaces: previous,
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )
        XCTAssertEqual(derived.spaces, previous, "Anomaly retention keeps the previous list")
        XCTAssertEqual(derived.activeSpaceID, 101, "activeSpaceID must be clamped into nextSpaces when retaining")
        XCTAssertTrue(derived.spaces.contains(where: { $0.id == derived.activeSpaceID }),
                      "Derived state must be single-epoch: activeSpaceID inside nextSpaces")
    }

    func testDeriveStateBuildsDesktopNumbersFromNativeOrder() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [
                SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
                SpaceIdentity(id: 201, display: "display-b", kind: .desktop),
                SpaceIdentity(id: 202, display: "display-b", kind: .fullscreen)
            ],
            activeByDisplay: ["display-a": 101, "display-b": 201],
            orderedIDsByDisplay: ["display-a": [101, 102], "display-b": [201, 202]]
        )

        let derived = service.deriveState(
            snapshot: snapshot, globalActiveID: 101, previousActiveID: nil, previousSpaces: [],
            previousNativeOrderByDisplay: [:],
            previousDesktopNumberBySpaceID: [:],
            consecutiveAnomalyRetentions: 0,
            maxConsecutiveAnomalyRetentions: SpaceStateManager.maxConsecutiveAnomalyRetentions
        )

        XCTAssertEqual(derived.nativeOrderByDisplay["display-a"], [101, 102])
        XCTAssertEqual(derived.nativeOrderByDisplay["display-b"], [201])
        XCTAssertEqual(derived.desktopNumberBySpaceID[101], 1)
        XCTAssertEqual(derived.desktopNumberBySpaceID[102], 2)
        XCTAssertEqual(derived.desktopNumberBySpaceID[201], 1)
        XCTAssertNil(derived.desktopNumberBySpaceID[202])
    }

    func testOrderedSpaceIDsSortByDesktopNumber() {
        let spaces = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
        ]

        let ordered = service.orderedSpaceIDs(
            spaces: spaces,
            desktopNumberBySpaceID: [101: 1, 102: 2, 103: 3]
        )

        XCTAssertEqual(ordered, [101, 102, 103])
    }

    func testSwitchableOrderedSpaceIDsExcludeNonDesktopSpaces() {
        let spaces = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .fullscreen),
            SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
        ]

        let ordered = service.switchableOrderedSpaceIDs(
            spaces: spaces,
            desktopNumberBySpaceID: [101: 1, 103: 2]
        )

        XCTAssertEqual(ordered, [101, 103])
    }
}
