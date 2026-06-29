import XCTest
import CoreGraphics
import AppKit
import Activation
import Core
@testable import StayHereApp

private final class MockCGSBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int?
    var managedSnapshotValue: CGSBridge.ManagedSnapshot
    var spacesForWindowMap: [Int: [Int]] = [:]

    init(
        activeSpaceIDValue: Int? = nil,
        managedSnapshotValue: CGSBridge.ManagedSnapshot = .init(
            spaces: [],
            activeByDisplay: [:],
            orderedIDsByDisplay: [:]
        )
    ) {
        self.activeSpaceIDValue = activeSpaceIDValue
        self.managedSnapshotValue = managedSnapshotValue
    }

    func activeSpaceID() -> Int? { activeSpaceIDValue }
    func managedSnapshot() -> CGSBridge.ManagedSnapshot { managedSnapshotValue }
    func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
    func switchByDesktopShortcut(index: Int) -> Bool { true }
    func spacesForWindow(windowID: Int) -> [Int] { spacesForWindowMap[windowID] ?? [] }
}

@MainActor
final class AllSpacesWindowSwitcherControllerTests: XCTestCase {
    private func makeWindow(
        pid: pid_t,
        windowID: Int,
        ownerName: String = "Notes",
        title: String = "Doc"
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowNumber as String: NSNumber(value: windowID),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
            kCGWindowOwnerName as String: ownerName,
            kCGWindowName as String: title
        ]
    }

    private func makeController(
        windowInfo: @escaping () -> [[String: Any]]? = { [] },
        focusedWindowID: @escaping () -> Int? = { nil },
        spacesForWindowMap: [Int: [Int]] = [:]
    ) -> (WindowSwitcherController, MockCGSBridge) {
        let spaces = [
            SpaceIdentity(id: 100, display: "display-a", kind: .desktop),
            SpaceIdentity(id: 200, display: "display-a", kind: .desktop)
        ]
        let snapshot = CGSBridge.ManagedSnapshot(
            spaces: spaces,
            activeByDisplay: ["display-a": 100],
            orderedIDsByDisplay: ["display-a": [100, 200]]
        )
        let bridge = MockCGSBridge(
            activeSpaceIDValue: 100,
            managedSnapshotValue: snapshot
        )
        bridge.spacesForWindowMap = spacesForWindowMap

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AllSpacesWindowSwitcherControllerTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let refreshSpaces = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())
        let switchSpace = SwitchSpaceUseCase(cgsBridge: bridge, repository: repository, refreshUseCase: refreshSpaces, logger: NoOpLogger())
        let listProvider = WindowListProvider(
            registry: repository,
            cgsBridge: bridge,
            settings: UserDefaultsSettingsRepository(),
            windowInfoProvider: windowInfo,
            runningApplicationProvider: { _ in nil },
            accessibilityWindowTitlesProvider: { _ in [:] },
            focusedWindowIDProvider: focusedWindowID,
            iconProvider: { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        )
        let focusService = WindowFocusService()
        let windowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: bridge,
            listProvider: listProvider,
            switchSpace: switchSpace,
            refreshSpaces: refreshSpaces,
            focusService: focusService
        ))
        let controller = WindowSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: repository,
            mode: .allSpaces,
            windowSwitchUseCase: windowSwitchUseCase,
            cgsBridge: bridge,
            listProvider: listProvider
        )
        return (controller, bridge)
    }

    private func waitForMainQueue(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "main-queue-drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    // MARK: - Per-space recency sorting

    func testWindowsWithinEachSpaceAreSortedByRecentUse() {
        let windows: [[String: Any]] = [
            makeWindow(pid: 10, windowID: 1, title: "Space1-Old"),
            makeWindow(pid: 11, windowID: 2, title: "Space1-Recent"),
            makeWindow(pid: 20, windowID: 3, title: "Space2-Old"),
            makeWindow(pid: 21, windowID: 4, title: "Space2-Recent")
        ]
        let spacesForWindow: [Int: [Int]] = [
            1: [100], 2: [100],
            3: [200], 4: [200]
        ]

        let (controller, _) = makeController(
            windowInfo: { windows },
            focusedWindowID: { nil },
            spacesForWindowMap: spacesForWindow
        )

        // First session — CGWindowList order [1,2,3,4], sessionOrder → [2,1,3,4]
        controller.openSwitcher()
        waitForMainQueue()
        // Commit window 2 (position 1)
        controller.commitSelection(at: 1)
        waitForMainQueue()
        waitForMainQueue()

        // Second session — recentWindowIDs = [2,1,3,4], sessionOrder → [1,2,3,4]
        controller.openSwitcher()
        waitForMainQueue()
        // Commit window 4 (position 4 in flat entries [1,2,3,4])
        controller.commitSelection(at: 4)
        waitForMainQueue()
        waitForMainQueue()

        // Third session — recentWindowIDs = [4,2,1,3]
        // recentEntries groups by space: Space1=[2,1], Space2=[4,3]
        controller.openSwitcher()
        waitForMainQueue()

        guard let spaceGroups = controller.testSessionSpaceGroups else {
            return XCTFail("Session space groups should exist")
        }

        let space1Group = spaceGroups.first(where: { $0.spaceID == 100 })
        let space2Group = spaceGroups.first(where: { $0.spaceID == 200 })

        XCTAssertEqual(space1Group?.entries.map(\.windowID), [2, 1],
                       "Space 1: recently used window (2) should precede old (1)")
        XCTAssertEqual(space2Group?.entries.map(\.windowID), [3, 4],
                       "Space 2: most recent non-focused (3) should precede focused (4)")
    }

    func testFocusedWindowIsFirstWithinItsSpaceGroup() {
        let windows: [[String: Any]] = [
            makeWindow(pid: 10, windowID: 1, title: "Space1-A"),
            makeWindow(pid: 11, windowID: 2, title: "Space1-B"),
            makeWindow(pid: 20, windowID: 3, title: "Space2-A"),
            makeWindow(pid: 21, windowID: 4, title: "Space2-B")
        ]
        let spacesForWindow: [Int: [Int]] = [
            1: [100], 2: [100],
            3: [200], 4: [200]
        ]

        let (controller, _) = makeController(
            windowInfo: { windows },
            focusedWindowID: { 2 },
            spacesForWindowMap: spacesForWindow
        )

        controller.openSwitcher()
        waitForMainQueue()

        guard let spaceGroups = controller.testSessionSpaceGroups else {
            return XCTFail("Session space groups should exist")
        }

        let space1Group = spaceGroups.first(where: { $0.spaceID == 100 })
        XCTAssertEqual(space1Group?.entries.map(\.windowID), [1, 2],
                       "Most recent non-focused (1) should precede focused (2) in Space 1 group")
    }

    func testSpaceGroupsPreserveOrderAcrossSessions() {
        let windows: [[String: Any]] = [
            makeWindow(pid: 10, windowID: 1, title: "Space1-A"),
            makeWindow(pid: 11, windowID: 2, title: "Space1-B"),
            makeWindow(pid: 20, windowID: 3, title: "Space2-A"),
            makeWindow(pid: 21, windowID: 4, title: "Space2-B")
        ]
        let spacesForWindow: [Int: [Int]] = [
            1: [100], 2: [100],
            3: [200], 4: [200]
        ]

        let (controller, _) = makeController(
            windowInfo: { windows },
            focusedWindowID: { nil },
            spacesForWindowMap: spacesForWindow
        )

        // First session
        controller.openSwitcher()
        waitForMainQueue()
        let firstGroups = controller.testSessionSpaceGroups
        XCTAssertEqual(firstGroups?.first(where: { $0.spaceID == 100 })?.entries.map(\.windowID), [2, 1])
        XCTAssertEqual(firstGroups?.first(where: { $0.spaceID == 200 })?.entries.map(\.windowID), [3, 4])

        // Select window 3 (Space 2), commit
        controller.commitSelection(at: 3)
        waitForMainQueue()
        waitForMainQueue()

        // Second session — window 3 should now be first in Space 2 group
        controller.openSwitcher()
        waitForMainQueue()

        guard let spaceGroups = controller.testSessionSpaceGroups else {
            return XCTFail("Session space groups should exist")
        }

        let space2Group = spaceGroups.first(where: { $0.spaceID == 200 })
        XCTAssertEqual(space2Group?.entries.map(\.windowID), [4, 3],
                       "Most recent non-focused (4) should precede committed (3) in Space 2 group")
    }

    func testEmptySpaceGroupsAreOmitted() {
        let windows: [[String: Any]] = [
            makeWindow(pid: 10, windowID: 1, title: "Space1-A")
        ]
        let spacesForWindow: [Int: [Int]] = [
            1: [100]
        ]

        let (controller, _) = makeController(
            windowInfo: { windows },
            spacesForWindowMap: spacesForWindow
        )

        controller.openSwitcher()
        waitForMainQueue()

        guard let spaceGroups = controller.testSessionSpaceGroups else {
            return XCTFail("Session space groups should exist")
        }

        let totalWindows = spaceGroups.reduce(0) { $0 + $1.entries.count }
        XCTAssertEqual(totalWindows, 1, "Only Space 1 should have entries")
        XCTAssertEqual(spaceGroups.first?.entries.first?.windowID, 1)
    }
}
