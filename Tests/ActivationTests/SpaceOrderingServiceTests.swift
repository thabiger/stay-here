import XCTest
@testable import Core

final class SpaceOrderingServiceTests: XCTestCase {
    private let service = SpaceOrderingService()

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

        let derived = service.deriveState(snapshot: snapshot, globalActiveID: 201, previousActiveID: nil)

        XCTAssertEqual(derived.spaces.map(\.id), [201, 202])
        XCTAssertEqual(derived.activeSpaceID, 201)
    }

    func testDeriveStateFallsBackWhenGlobalActiveSpaceIsMissing() {
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: [],
            activeByDisplay: [:],
            orderedIDsByDisplay: [:]
        )

        let derived = service.deriveState(snapshot: snapshot, globalActiveID: nil, previousActiveID: nil)

        XCTAssertEqual(derived.spaces, [SpaceIdentity(id: 1, display: "fallback-display")])
        XCTAssertEqual(derived.activeSpaceID, 1)
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

        let derived = service.deriveState(snapshot: snapshot, globalActiveID: 101, previousActiveID: nil)

        XCTAssertEqual(derived.nativeOrderByDisplay["display-a"], [101, 102])
        XCTAssertEqual(derived.nativeOrderByDisplay["display-b"], [201])
        XCTAssertEqual(derived.desktopNumberBySpaceID[101], 1)
        XCTAssertEqual(derived.desktopNumberBySpaceID[102], 2)
        XCTAssertEqual(derived.desktopNumberBySpaceID[201], 1)
        XCTAssertNil(derived.desktopNumberBySpaceID[202])
    }

    func testOrderedSpaceIDsMergeCustomOrderWithDiscoveredSpaces() {
        let spaces = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
        ]

        let ordered = service.orderedSpaceIDs(
            spaces: spaces,
            displayOrder: [103, 101],
            usesCustomDisplayOrder: true,
            desktopNumberBySpaceID: [101: 1, 102: 2, 103: 3]
        )

        XCTAssertEqual(ordered, [103, 101, 102])
    }

    func testSwitchableOrderedSpaceIDsExcludeNonDesktopSpaces() {
        let spaces = [
            SpaceIdentity(id: 101, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 102, display: "display-a", kind: .fullscreen),
            SpaceIdentity(id: 103, display: "display-a", kind: .desktop)
        ]

        let ordered = service.switchableOrderedSpaceIDs(
            spaces: spaces,
            displayOrder: [102, 103, 101],
            usesCustomDisplayOrder: true,
            desktopNumberBySpaceID: [101: 1, 103: 2]
        )

        XCTAssertEqual(ordered, [103, 101])
    }
}
