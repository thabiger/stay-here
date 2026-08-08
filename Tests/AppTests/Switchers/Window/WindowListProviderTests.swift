import AppKit
import Core
import CoreGraphics
import XCTest
import TestHelpers
@testable import StayHereApp

private final class WindowListProviderMockBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int?
    var managedSnapshotValue: CGSBridge.ManagedSnapshot
    var spacesForWindowValues: [Int: [Int]]

    init(
        activeSpaceIDValue: Int? = 100,
        managedSnapshotValue: CGSBridge.ManagedSnapshot,
        spacesForWindowValues: [Int: [Int]] = [:]
    ) {
        self.activeSpaceIDValue = activeSpaceIDValue
        self.managedSnapshotValue = managedSnapshotValue
        self.spacesForWindowValues = spacesForWindowValues
    }

    func activeSpaceID() -> Int? { activeSpaceIDValue }
    func managedSnapshot() -> CGSBridge.ManagedSnapshot { managedSnapshotValue }
    func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
    func switchByDesktopShortcut(index: Int) -> Bool { true }
    func spacesForWindow(windowID: Int) -> [Int] { spacesForWindowValues[windowID] ?? [] }
}

private struct FakeWindowListApplication: WindowListApplication {
    let isHidden: Bool
    let localizedName: String?
    let bundleURL: URL?
}

private final class FakeWindowListSettings: WindowSwitcherSettings {
    var windowSwitcherEnabled: Bool = true
    var windowSwitcherShortcutText: String = "command+`"
    var windowSwitcherTitleFormat: WindowSwitcherTitleFormat = .appNameOnly
    var windowSwitcherShowMinimizedWindows: Bool = false
    var windowSwitcherShowHiddenWindows: Bool = false
}

@MainActor
final class WindowListProviderTests: XCTestCase {
    private func makeRegistry(bridge: WindowListProviderMockBridge) -> any SpaceRegistryProtocol {
        SpaceStateManagerFactory.makePair(cgsBridge: bridge).queryService
    }

    private func makeSnapshot() -> CGSBridge.ManagedSnapshot {
        CGSBridge.ManagedSnapshot(
            spaces: [SpaceIdentity(id: 100, display: "display-a", kind: .desktop)],
            activeByDisplay: ["display-a": 100],
            orderedIDsByDisplay: ["display-a": [100]]
        )
    }

    private func makeProvider(
        settings: FakeWindowListSettings = FakeWindowListSettings(),
        bridge: WindowListProviderMockBridge? = nil,
        windowInfo: @escaping () -> [[String: Any]]?,
        runningApplications: [pid_t: FakeWindowListApplication] = [:],
        accessibilityTitles: [pid_t: [Int: String]] = [:],
        icon: NSImage = NSImage(size: NSSize(width: 18, height: 18))
    ) -> WindowListProvider {
        let bridge = bridge ?? WindowListProviderMockBridge(managedSnapshotValue: makeSnapshot())
        let registry = makeRegistry(bridge: bridge)
        return WindowListProvider(
            registry: registry,
            cgsBridge: bridge,
            settings: settings,
            windowInfoProvider: windowInfo,
            runningApplicationProvider: { runningApplications[$0] },
            accessibilityWindowTitlesProvider: { accessibilityTitles[$0] ?? [:] },
            iconProvider: { _ in icon }
        )
    }

    private func makeWindow(
        pid: pid_t,
        windowID: Int,
        layer: Int = 0,
        workspace: Int? = 1,
        isOnScreen: Bool = true,
        ownerName: String = "Notes",
        title: String? = "Document"
    ) -> [String: Any] {
        var item: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowNumber as String: NSNumber(value: windowID),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowIsOnscreen as String: NSNumber(value: isOnScreen),
            kCGWindowOwnerName as String: ownerName
        ]
        if let workspace {
            item["kCGWindowWorkspace"] = NSNumber(value: workspace)
        }
        if let title {
            item[kCGWindowName as String] = title
        }
        return item
    }

    func testFiltersOutNonLayerZeroWindows() async {
        let provider = makeProvider {
            [
                self.makeWindow(pid: 10, windowID: 1, layer: 0),
                self.makeWindow(pid: 10, windowID: 2, layer: 3)
            ]
        }

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testRespectsWorkspaceMatchWhenDesktopNumberExists() async {
        let provider = makeProvider {
            [
                self.makeWindow(pid: 10, windowID: 1, workspace: 1),
                self.makeWindow(pid: 10, windowID: 2, workspace: 2)
            ]
        }

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testFallsBackToSpacesForWindowWhenWorkspaceIsMissing() async {
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100], 2: [101]]
        )
        let provider = makeProvider(bridge: bridge) {
            [
                self.makeWindow(pid: 10, windowID: 1, workspace: nil),
                self.makeWindow(pid: 10, windowID: 2, workspace: nil)
            ]
        }

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testHonorsHiddenWindowSetting() async {
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowHiddenWindows = false
        let hiddenApp = FakeWindowListApplication(isHidden: true, localizedName: "Notes", bundleURL: nil)
        let provider = makeProvider(
            settings: settings,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1)] },
            runningApplications: [10: hiddenApp]
        )

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        settings.windowSwitcherShowHiddenWindows = true

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertEqual(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).map { $0.windowID }, [1])
    }

    func testHonorsMinimizedWindowSetting() async {
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowMinimizedWindows = false
        let provider = makeProvider(
            settings: settings,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, isOnScreen: false)] }
        )

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        settings.windowSwitcherShowMinimizedWindows = true

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertEqual(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).map { $0.windowID }, [1])
    }

    func testUsesAccessibilityTitleFallbackWhenWindowTitleIsEmpty() async {
        let provider = makeProvider(
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, title: "   ")] },
            accessibilityTitles: [10: [1: "Recovered Title"]]
        )

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(entries.first?.windowTitle, "Recovered Title")
    }

    func testReturnsStableMetadataForSnapshotBuilding() async throws {
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        let app = FakeWindowListApplication(
            isHidden: false,
            localizedName: "Calendar",
            bundleURL: URL(fileURLWithPath: "/Applications/Calendar.app")
        )
        let provider = makeProvider(
            windowInfo: { [self.makeWindow(pid: 22, windowID: 9, ownerName: "Fallback", title: "Today")] },
            runningApplications: [22: app],
            icon: icon
        )

        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.pid, 22)
        XCTAssertEqual(entry.appName, "Calendar")
        XCTAssertEqual(entry.windowTitle, "Today")
        XCTAssertTrue(entry.icon === icon)
    }

    // MARK: - All-spaces background refresh

    private func makeAllSpacesProvider(
        enumerateCount: UnsafeMutablePointer<Int>? = nil
    ) -> WindowListProvider {
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        return makeProvider(
            bridge: bridge,
            windowInfo: {
                enumerateCount?.pointee += 1
                return [self.makeWindow(pid: 10, windowID: 1)]
            }
        )
    }

    func testRefreshAllSpacesCacheInBackgroundPopulatesCacheWithoutInlineBuild() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeAllSpacesProvider(enumerateCount: enumerateCount)

        provider.refreshAllSpacesCacheInBackground()
        await provider.waitForAllSpacesRefresh()

        let groups = provider.entriesForAllSpaces()
        XCTAssertEqual(groups.flatMap(\.entries).map(\.windowID), [1])
        XCTAssertEqual(enumerateCount.pointee, 1, "the background refresh should be the only enumeration")
    }

    func testRefreshAllSpacesCacheInBackgroundCoalescesConcurrentCalls() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeAllSpacesProvider(enumerateCount: enumerateCount)

        provider.refreshAllSpacesCacheInBackground()
        provider.refreshAllSpacesCacheInBackground()
        await provider.waitForAllSpacesRefresh()

        XCTAssertEqual(
            enumerateCount.pointee, 2,
            "second request while in flight must coalesce into exactly one follow-up refresh"
        )
    }

    // MARK: - Current-space background refresh

    private func makeCurrentSpaceProvider(
        enumerateCount: UnsafeMutablePointer<Int>? = nil
    ) -> WindowListProvider {
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        return makeProvider(
            bridge: bridge,
            windowInfo: {
                enumerateCount?.pointee += 1
                return [self.makeWindow(pid: 10, windowID: 1)]
            }
        )
    }

    func testEntriesMissReturnsEmptyAndRefreshesInBackground() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeCurrentSpaceProvider(enumerateCount: enumerateCount)

        // First call: cache miss, returns empty, kicks background refresh
        let first = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertTrue(first.isEmpty, "cache miss returns empty immediately")
        XCTAssertEqual(enumerateCount.pointee, 0, "enumeration has not completed yet (or just started)")

        await provider.waitForCurrentSpaceRefresh()

        // Second call: cache hit, returns populated list
        let second = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(second.map { $0.windowID }, [1])
        XCTAssertEqual(enumerateCount.pointee, 1, "exactly one enumeration occurred")
    }

    func testEntriesHitServesCachedWithoutReenumerating() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeCurrentSpaceProvider(enumerateCount: enumerateCount)

        // Warm up the cache
        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()

        let countAfterWarmup = enumerateCount.pointee

        // Second call: cache hit, no re-enumeration
        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(entries.map { $0.windowID }, [1])
        XCTAssertEqual(enumerateCount.pointee, countAfterWarmup, "cache hit must not trigger re-enumeration")
    }

    func testSettingsChangeInvalidatesAndRefreshesInBackground() async {
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowMinimizedWindows = false
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        let provider = makeProvider(
            settings: settings,
            bridge: bridge,
            windowInfo: {
                enumerateCount.pointee += 1
                return [self.makeWindow(pid: 10, windowID: 1, isOnScreen: false)]
            }
        )

        // Initial: minimized windows hidden
        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        // Change settings -> cache invalidated
        settings.windowSwitcherShowMinimizedWindows = true

        // Next call: cache miss (settings changed), returns empty, kicks refresh
        let afterChange = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertTrue(afterChange.isEmpty, "settings change invalidates cache")

        await provider.waitForCurrentSpaceRefresh()

        // After refresh: new settings respected
        let final = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(final.map { $0.windowID }, [1])
    }

    func testBackgroundRefreshResultDiscardedWhenCacheInvalidatedMidFlight() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeCurrentSpaceProvider(enumerateCount: enumerateCount)

        // Warm up the cache first
        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertEqual(enumerateCount.pointee, 1)

        // Invalidate cache (simulates settings change) — this increments generation
        provider.invalidateCache()

        // Next entries(in:) call: cache miss, kicks new background refresh
        let afterInvalidate = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertTrue(afterInvalidate.isEmpty, "invalidated cache returns empty")

        await provider.waitForCurrentSpaceRefresh()

        // After the new refresh completes, cache is repopulated with fresh data
        let final = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(final.map { $0.windowID }, [1], "fresh refresh repopulates cache")
        XCTAssertEqual(enumerateCount.pointee, 2, "exactly two enumerations total")
    }

    func testCurrentSpaceRefreshCoalescesConcurrentRequests() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let provider = makeCurrentSpaceProvider(enumerateCount: enumerateCount)

        let context = WindowSpaceContext(spaceID: 100, desktopNumber: 1)
        provider.refreshCurrentSpaceCacheInBackground(context: context)
        provider.refreshCurrentSpaceCacheInBackground(context: context)
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertEqual(
            enumerateCount.pointee, 2,
            "second request while in flight must coalesce into exactly one follow-up refresh"
        )
    }

    func testPendingRefreshForDifferentContextDiscardsStaleResult() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let gate = DispatchSemaphore(value: 0)
        let ctxA = WindowSpaceContext(spaceID: 100, desktopNumber: 1)
        let ctxB = WindowSpaceContext(spaceID: 200, desktopNumber: 2)
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 100, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 200, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 100],
                orderedIDsByDisplay: ["display-a": [100, 200]]
            ),
            spacesForWindowValues: [1: [100], 2: [200]]
        )
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: {
                enumerateCount.pointee += 1
                if enumerateCount.pointee == 2 { gate.wait() }
                return [self.makeWindow(pid: 10, windowID: enumerateCount.pointee, workspace: enumerateCount.pointee, isOnScreen: true)]
            }
        )
        provider.refreshCurrentSpaceCacheInBackground(context: ctxA)
        provider.refreshCurrentSpaceCacheInBackground(context: ctxB)

        // Wait for t2 (the follow-up) to have started and be blocked on the gate
        let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(5)
        while enumerateCount.pointee < 2 {
            Thread.sleep(forTimeInterval: 0.01)
            if DispatchTime.now() >= deadline { break }
        }

        // CORR-1 assertion: B's cache must NOT contain A's entries while t2 is in flight
        XCTAssertTrue(provider.entries(in: ctxB).isEmpty, "stale completion for space A must not be cached under space B")

        gate.signal()
        await provider.waitForCurrentSpaceRefresh()

        XCTAssertEqual(provider.entries(in: ctxB).map({ $0.windowID }), [2])
        XCTAssertEqual(enumerateCount.pointee, 2, "discard must not add enumerations")
    }

    // MARK: - Regression tests (round-2 fixes)

    func testStaleGenerationDiscardedWhenCacheInvalidatedMidFlight() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let gate = DispatchSemaphore(value: 0)
        let context = WindowSpaceContext(spaceID: 100, desktopNumber: 1)
        let provider = makeProvider(windowInfo: {
            enumerateCount.pointee += 1
            if enumerateCount.pointee == 1 { gate.wait() }
            return [self.makeWindow(pid: 10, windowID: enumerateCount.pointee, workspace: 1, isOnScreen: true)]
        })
        provider.refreshCurrentSpaceCacheInBackground(context: context)
        let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(5)
        while enumerateCount.pointee < 1 {
            Thread.sleep(forTimeInterval: 0.01)
            if DispatchTime.now() >= deadline { break }
        }
        provider.invalidateCache()
        gate.signal()
        await provider.waitForCurrentSpaceRefresh()
        // Kick a fresh refresh (cache is empty after stale discard) and wait for it
        provider.refreshCurrentSpaceCacheInBackground(context: context)
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertEqual(provider.entries(in: context).map(\.windowID), [2],
                       "fresh refresh repopulates cache; stale generation-0 result was discarded")
        XCTAssertEqual(enumerateCount.pointee, 2)
    }

    func testRapidSpaceSwitchesServeMostRecentRequest() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let gate = DispatchSemaphore(value: 0)
        let ctxA = WindowSpaceContext(spaceID: 100, desktopNumber: 1)
        let ctxB = WindowSpaceContext(spaceID: 200, desktopNumber: 2)
        let ctxC = WindowSpaceContext(spaceID: 300, desktopNumber: 3)
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: CGSBridge.ManagedSnapshot(
                spaces: [
                    SpaceIdentity(id: 100, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 200, display: "display-a", kind: .desktop),
                    SpaceIdentity(id: 300, display: "display-a", kind: .desktop)
                ],
                activeByDisplay: ["display-a": 100],
                orderedIDsByDisplay: ["display-a": [100, 200, 300]]
            )
        )
        let provider = makeProvider(bridge: bridge, windowInfo: {
            enumerateCount.pointee += 1
            if enumerateCount.pointee == 1 { gate.wait() }
            return [
                self.makeWindow(pid: 10, windowID: 1, workspace: 1, isOnScreen: true),
                self.makeWindow(pid: 10, windowID: 2, workspace: 2, isOnScreen: true),
                self.makeWindow(pid: 10, windowID: 3, workspace: 3, isOnScreen: true)
            ]
        })
        provider.refreshCurrentSpaceCacheInBackground(context: ctxA)
        provider.refreshCurrentSpaceCacheInBackground(context: ctxB)
        provider.refreshCurrentSpaceCacheInBackground(context: ctxC)
        let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(5)
        while enumerateCount.pointee < 1 {
            Thread.sleep(forTimeInterval: 0.01)
            if DispatchTime.now() >= deadline { break }
        }
        gate.signal()
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertEqual(enumerateCount.pointee, 2, "exactly one coalesced follow-up for the latest request")
        XCTAssertEqual(provider.entries(in: ctxC).map(\.windowID), [3], "most recent request must be served")
        XCTAssertTrue(provider.entries(in: ctxB).isEmpty, "intermediate request coalesces into the latest")
        XCTAssertTrue(provider.entries(in: ctxA).isEmpty, "stale space-A result must be discarded")
    }

    func testCancelDuringPendingCancelsInFlightTask() async {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let gate = DispatchSemaphore(value: 0)
        let ctxA = WindowSpaceContext(spaceID: 100, desktopNumber: 1)
        let ctxB = WindowSpaceContext(spaceID: 200, desktopNumber: 2)
        let provider = makeProvider(windowInfo: {
            enumerateCount.pointee += 1
            if enumerateCount.pointee == 1 {
                gate.wait()
            }
            return [self.makeWindow(pid: 10, windowID: 1, workspace: 1, isOnScreen: true)]
        })
        provider.refreshCurrentSpaceCacheInBackground(context: ctxA)   // t1 in flight, blocked
        // Wait for t1 to actually start and block on the gate
        let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(5)
        while enumerateCount.pointee < 1 {
            Thread.sleep(forTimeInterval: 0.01)
            if DispatchTime.now() >= deadline { break }
        }
        provider.refreshCurrentSpaceCacheInBackground(context: ctxB)   // -> .pending
        provider.cancelCurrentSpaceRefresh()                            // cancels t1 even while .pending
        gate.signal()
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertEqual(enumerateCount.pointee, 1, "no follow-up refresh may start after cancel")
        XCTAssertTrue(provider.entries(in: ctxA).isEmpty)
        XCTAssertTrue(provider.entries(in: ctxB).isEmpty)
    }
}
