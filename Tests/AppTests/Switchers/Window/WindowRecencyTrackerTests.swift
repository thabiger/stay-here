import XCTest
import AppKit
import CoreGraphics
import Core
@testable import StayHereApp

final class WindowRecencyTrackerTests: XCTestCase {
    private func makeEntry(windowID: Int) -> WindowEntry {
        WindowEntry(
            windowID: windowID,
            pid: pid_t(windowID),
            appName: "App\(windowID)",
            windowTitle: "Window \(windowID)",
            icon: NSImage(size: NSSize(width: 18, height: 18))
        )
    }

    private func makeGroup(spaceID: Int, entries: [WindowEntry]) -> SpaceWindowGroup {
        SpaceWindowGroup(spaceID: spaceID, spaceLabel: "Space \(spaceID)", entries: entries)
    }

    private func makeSession(spaceID: Int, ids: [Int], starting: Int?) -> WindowSwitcherSession {
        let entries = ids.map(makeEntry(windowID:))
        return WindowSwitcherSession(
            startingWindowID: starting,
            selectedWindowID: ids.first,
            shortcut: SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand]),
            spaceGroups: [makeGroup(spaceID: spaceID, entries: entries)],
            flatEntries: entries,
            trigger: .keyboard
        )
    }

    private func seed(_ tracker: WindowRecencyTracker, _ ids: [Int]) {
        for id in ids {
            tracker.recordSelection(id, in: nil, scope: .complete)
        }
    }

    func testCompleteListingReordersAndPrunes() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [1, 2, 3])
        XCTAssertEqual(tracker.recentWindowIDs, [3, 2, 1])

        let (entries, _, mergedOrder) = tracker.orderedEntriesAndGroups(
            from: [
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 4)]),
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 3)])
            ],
            scope: .complete
        )

        XCTAssertEqual(entries.map(\.windowID), [3, 4])
        XCTAssertEqual(mergedOrder, [3, 4],
                       "Complete listing replaces the list: known ID 3 keeps recency, stale 1/2 pruned, unknown 4 appended")
        XCTAssertEqual(tracker.recentWindowIDs, [3, 2, 1],
                       "Query is pure: state unchanged until apply")

        tracker.apply(order: mergedOrder)
        XCTAssertEqual(tracker.recentWindowIDs, [3, 4],
                       "apply reproduces the old write-on-read result")
    }

    func testSubsetListingPreservesOtherSpaceOrdering() {
        let tracker = WindowRecencyTracker()
        // Seed MRU order [A3, B1, A2, A1]; A windows: 101, 102, 103; B window: 201
        seed(tracker, [101, 102, 201, 103])
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101])

        let (entries, _, mergedOrder) = tracker.orderedEntriesAndGroups(
            from: [makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201)])],
            scope: .subset
        )

        XCTAssertEqual(entries.map(\.windowID), [201])
        XCTAssertEqual(mergedOrder, [201, 103, 102, 101],
                       "Subset listing keeps other-space IDs in their prior order")
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101],
                       "Query is pure: state unchanged until apply")

        tracker.apply(order: mergedOrder)
        XCTAssertEqual(tracker.recentWindowIDs, [201, 103, 102, 101])
    }

    func testEmptySubsetListingDoesNotWipe() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [101, 102, 201, 103])

        let (entries, groups, mergedOrder) = tracker.orderedEntriesAndGroups(
            from: [makeGroup(spaceID: 100, entries: [])],
            scope: .subset
        )

        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(groups.isEmpty)
        XCTAssertEqual(mergedOrder, [103, 201, 102, 101],
                       "Empty subset listing preserves the full prior order")
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101],
                       "Empty subset listing must not wipe the shared recency list")

        tracker.apply(order: mergedOrder)
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101])
    }

    func testEmptyCompleteListingWipes() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [101, 102, 201, 103])

        let (entries, _, mergedOrder) = tracker.orderedEntriesAndGroups(
            from: [makeGroup(spaceID: 100, entries: [])],
            scope: .complete
        )

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(mergedOrder, [],
                       "Empty complete listing is authoritative and prunes all IDs")
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101],
                       "Query is pure: state unchanged until apply")

        tracker.apply(order: mergedOrder)
        XCTAssertEqual(tracker.recentWindowIDs, [])
    }

    func testSubsetCommitPreservesCrossSpaceOrder() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [101, 102, 201, 103])

        let session = makeSession(spaceID: 100, ids: [302, 301], starting: 301)
        tracker.recordSelection(302, in: session, scope: .subset)

        XCTAssertEqual(tracker.recentWindowIDs, [302, 301, 103, 201, 102, 101],
                       "Subset commit keeps IDs outside the session in their prior order")
    }

    func testCompleteCommitPrunesStaleIDs() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [101, 102, 201, 103])

        let session = makeSession(spaceID: 100, ids: [302, 301], starting: 301)
        tracker.recordSelection(302, in: session, scope: .complete)

        XCTAssertEqual(tracker.recentWindowIDs, [302, 301],
                       "Complete commit replaces the list and prunes stale IDs")
    }

    func testIssueScenarioEndToEnd() {
        let tracker = WindowRecencyTracker()
        // MRU order [102, 201, 101, 202]; A windows: 101, 102; B windows: 201, 202
        seed(tracker, [202, 101, 201, 102])
        XCTAssertEqual(tracker.recentWindowIDs, [102, 201, 101, 202])

        // 1. All-spaces open (complete): authoritative, list unchanged.
        let (_, _, openOrder1) = tracker.orderedEntriesAndGroups(
            from: [
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 102), makeEntry(windowID: 101)]),
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201), makeEntry(windowID: 202)])
            ],
            scope: .complete
        )
        tracker.apply(order: openOrder1)
        XCTAssertEqual(tracker.recentWindowIDs, [102, 201, 101, 202])

        // 2. Current-space open (subset): must retain B windows.
        let (_, _, openOrder2) = tracker.orderedEntriesAndGroups(
            from: [makeGroup(spaceID: 100, entries: [makeEntry(windowID: 102), makeEntry(windowID: 101)])],
            scope: .subset
        )
        tracker.apply(order: openOrder2)
        XCTAssertEqual(tracker.recentWindowIDs, [102, 101, 201, 202],
                       "Subset open keeps cross-space MRU order")

        // 3. All-spaces open (complete) with B windows in raw enumeration order
        // (202 before 201): B windows must still appear in MRU order.
        let (entries, groups, openOrder3) = tracker.orderedEntriesAndGroups(
            from: [
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 202), makeEntry(windowID: 201)]),
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 102), makeEntry(windowID: 101)])
            ],
            scope: .complete
        )
        tracker.apply(order: openOrder3)

        XCTAssertEqual(tracker.recentWindowIDs, [102, 101, 201, 202],
                       "Non-current-space windows survive in MRU order after the issue flow")
        XCTAssertEqual(entries.map(\.windowID), [102, 101, 201, 202])
        XCTAssertEqual(groups.first(where: { $0.spaceID == 200 })?.entries.map(\.windowID), [201, 202],
                       "Space B windows are MRU-ordered (201 before 202), not enumeration-ordered")
    }

    func testOrderedEntriesAndGroupsNeverMutates() {
        let tracker = WindowRecencyTracker()
        seed(tracker, [101, 102, 201, 103])
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101])

        _ = tracker.orderedEntriesAndGroups(
            from: [makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201)])],
            scope: .subset
        )
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101],
                       "Subset query must not mutate state")

        _ = tracker.orderedEntriesAndGroups(
            from: [
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 102), makeEntry(windowID: 101)]),
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201)])
            ],
            scope: .complete
        )
        XCTAssertEqual(tracker.recentWindowIDs, [103, 201, 102, 101],
                       "Complete query must not mutate state")
    }

    func testGroupedBySpaceOrdersSpacesByMostRecentEntry() {
        let groups = WindowRecencyTracker.groupedBySpace(
            ordered: [
                .init(spaceID: 200, entry: makeEntry(windowID: 202)),
                .init(spaceID: 100, entry: makeEntry(windowID: 101)),
                .init(spaceID: 100, entry: makeEntry(windowID: 102)),
                .init(spaceID: 200, entry: makeEntry(windowID: 201))
            ],
            from: [
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 101), makeEntry(windowID: 102)]),
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201), makeEntry(windowID: 202)])
            ]
        )
        XCTAssertEqual(groups.map(\.spaceID), [200, 100],
                       "Spaces ordered by their most-recent entry (202 before 101)")
        XCTAssertEqual(groups[0].entries.map(\.windowID), [202, 201],
                       "Space 200 entries in recency order")
        XCTAssertEqual(groups[1].entries.map(\.windowID), [101, 102],
                       "Space 100 entries in recency order")
    }

    func testGroupedBySpaceDropsSpacesWithNoSurvivingEntries() {
        let groups = WindowRecencyTracker.groupedBySpace(
            ordered: [.init(spaceID: 100, entry: makeEntry(windowID: 101))],
            from: [
                makeGroup(spaceID: 100, entries: [makeEntry(windowID: 101)]),
                makeGroup(spaceID: 200, entries: [makeEntry(windowID: 201)])
            ]
        )
        XCTAssertEqual(groups.map(\.spaceID), [100],
                       "Spaces with no entries in the ordered list are dropped — no phantom groups (regression guard for the removed -1 sentinel)")
    }

    func testGroupedBySpaceWithEmptyOrderedInputReturnsEmptyGroups() {
        let groups = WindowRecencyTracker.groupedBySpace(
            ordered: [],
            from: [makeGroup(spaceID: 100, entries: [makeEntry(windowID: 101)])]
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testApplyCapsRecentWindowIDsAtLimit() {
        let tracker = WindowRecencyTracker()
        tracker.apply(order: Array(0..<600))
        XCTAssertEqual(tracker.recentWindowIDs.count, 512)
        XCTAssertEqual(tracker.recentWindowIDs, Array(0..<512))
    }
}
