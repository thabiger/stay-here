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

    private let callLock = NSLock()
    private var _spacesForWindowCallCount = 0
    private var _clearSpacesCacheCallCount = 0

    var spacesForWindowCallCount: Int {
        callLock.lock()
        defer { callLock.unlock() }
        return _spacesForWindowCallCount
    }

    var clearSpacesCacheCallCount: Int {
        callLock.lock()
        defer { callLock.unlock() }
        return _clearSpacesCacheCallCount
    }

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
    func spacesForWindow(windowID: Int) -> [Int] {
        callLock.lock()
        _spacesForWindowCallCount += 1
        callLock.unlock()
        return spacesForWindowValues[windowID] ?? []
    }

    func clearSpacesCache() {
        callLock.lock()
        _clearSpacesCacheCallCount += 1
        callLock.unlock()
    }
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

/// Records AX provider invocations with thread info for PERF-2 testing.
private final class ThreadSafeAXInvocationRecorder {
    private let lock = NSLock()
    private var invocations: [Bool] = []

    func record(isMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        invocations.append(isMainThread)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocations.count
    }

    var allOffMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !invocations.contains(true)
    }
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
        icon: NSImage = NSImage(size: NSSize(width: 18, height: 18)),
        axInvocationRecorder: ThreadSafeAXInvocationRecorder? = nil
    ) -> WindowListProvider {
        let bridge = bridge ?? WindowListProviderMockBridge(managedSnapshotValue: makeSnapshot())
        let registry = makeRegistry(bridge: bridge)
        return WindowListProvider(
            registry: registry,
            cgsBridge: bridge,
            settings: settings,
            windowInfoProvider: windowInfo,
            runningApplicationProvider: { runningApplications[$0] },
            accessibilityWindowTitlesProvider: { pid in
                let titles = accessibilityTitles[pid] ?? [:]
                axInvocationRecorder?.record(isMainThread: Thread.isMainThread)
                return titles
            },
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

    // MARK: - PERF-2: All-spaces cold inline fallback

    func testAllSpacesColdInlineFallbackNeverCallsAccessibilityProviderOnMainThread() async {
        let axInvocations = ThreadSafeAXInvocationRecorder()
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        // Window with no CGWindow name so AX path is exercised by the background refresh
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, title: nil)] },
            accessibilityTitles: [10: [1: "AX Title"]],
            axInvocationRecorder: axInvocations
        )

        // Cold call — no prior warm-up
        let groups = provider.entriesForAllSpaces()
        XCTAssertFalse(groups.isEmpty, "inline fallback must return non-empty groups")
        XCTAssertEqual(groups.flatMap(\.entries).map(\.windowID), [1])

        // Wait for the kicked background refresh to complete
        await provider.waitForAllSpacesRefresh()

        // PERF-2 invariant: AX was invoked (by background refresh) but never on main thread
        XCTAssertGreaterThan(axInvocations.count, 0, "background refresh must have called the AX provider")
        XCTAssertTrue(
            axInvocations.allOffMainThread,
            "PERF-2: AX provider must never be called on the main thread"
        )
    }

    func testAllSpacesColdInlineFallbackSkipsAXAndBackgroundRefreshUpgradesTitles() async throws {
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        // Window with no CGWindow name (title: nil) so rawName is empty
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, title: nil)] },
            accessibilityTitles: [10: [1: "AX Title"]]
        )

        // Cold inline fallback — AX skipped, so title is nil (falls back to app name)
        let groups = provider.entriesForAllSpaces()
        let entry = try XCTUnwrap(groups.flatMap(\.entries).first)
        XCTAssertEqual(entry.windowTitle, nil, "cold inline must skip AX — rawName is empty, so title is nil")

        // Wait for the kicked background refresh to complete
        await provider.waitForAllSpacesRefresh()

        // After background refresh, cache holds full AX titles
        let refreshedGroups = provider.entriesForAllSpaces()
        let refreshedEntry = try XCTUnwrap(refreshedGroups.flatMap(\.entries).first)
        XCTAssertEqual(refreshedEntry.windowTitle, "AX Title", "background refresh must self-heal titles")
    }

    func testAllSpacesInlineFallbackResolvesEachWindowExactlyOnce() async {
        // 2 on-screen windows that both resolve to space 100 (the only managed space).
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100], 2: [100]]
        )
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: {
                [
                    self.makeWindow(pid: 10, windowID: 1, workspace: 1, isOnScreen: true),
                    self.makeWindow(pid: 10, windowID: 2, workspace: nil, isOnScreen: true)
                ]
            }
        )

        let groups = provider.entriesForAllSpaces()

        // Both windows pass the filter and appear in groups under space 100.
        let allWindowIDs = Set(groups.flatMap(\.entries).map(\.windowID))
        XCTAssertEqual(allWindowIDs, [1, 2], "all windows should appear in groups")

        // Wait for the kicked background refresh to complete.
        await provider.waitForAllSpacesRefresh()

        // Inline filter: 2 calls (one per window).
        // Background refresh: 2 calls (one per window, via AllSpacesWindowComputer).
        // Grouper: 0 calls (uses preResolvedSpaceIDs from the inline path).
        // Before the fix: grouper would add 2 more calls → total 6.
        XCTAssertEqual(bridge.spacesForWindowCallCount, 4,
                       "filter + background refresh = 4 calls; grouper makes zero (pre-resolved)")
    }

    func testAllSpacesInlineFallbackGrouperMakesNoCGSCalls() async {
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100], 2: [100]]
        )
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: {
                [
                    self.makeWindow(pid: 10, windowID: 1, workspace: 1, isOnScreen: true),
                    self.makeWindow(pid: 10, windowID: 2, workspace: nil, isOnScreen: true)
                ]
            }
        )

        let groups = provider.entriesForAllSpaces()

        // Both windows pass the filter and get spaceIDs resolved by the filter.
        // The grouper should use preResolvedSpaceIDs — no additional CGS calls.
        // Verify grouping is correct
        guard let group = groups.first else {
            XCTFail("expected at least one group")
            return
        }
        XCTAssertEqual(group.spaceID, 100)
        XCTAssertEqual(Set(group.entries.map(\.windowID)), [1, 2])

        // Wait for background refresh to complete
        await provider.waitForAllSpacesRefresh()

        // 2 (inline filter) + 2 (background refresh) = 4 total.
        // Before the fix: 2 (filter) + 2 (grouper) + 2 (background) = 6.
        XCTAssertEqual(bridge.spacesForWindowCallCount, 4,
                       "grouper must make zero CGS calls (uses pre-resolved map)")
    }

    // MARK: - ARCH-1: inline fallback refresh vs invalidate() race

    func testAllSpacesInlineFallbackKickDiscardedAfterInvalidateSelfHeals() async throws {
        let enumerateCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        enumerateCount.initialize(to: 0)
        defer { enumerateCount.deallocate() }
        let gate = DispatchSemaphore(value: 0)
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        // Window with no CGWindow name (title: nil) so inline entries are AX-skipped.
        // Block ONLY enumeration #2 (the inline-fallback kick); #1 (inline) and
        // later enumerations must never block (they run on the main actor / are needed to finish).
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: {
                enumerateCount.pointee += 1
                if enumerateCount.pointee == 2 { gate.wait() }
                return [self.makeWindow(pid: 10, windowID: 1, title: nil)]
            },
            accessibilityTitles: [10: [1: "AX Title"]]
        )

        // 1. Cold open: inline fallback populates the cache with AX-skipped entries
        //    (title nil), then kicks a background refresh that blocks on the gate.
        let groups = provider.entriesForAllSpaces()
        XCTAssertEqual(groups.flatMap(\.entries).first?.windowTitle, nil,
                       "cold inline fallback must skip AX (rawName empty -> nil title)")

        // 2. Wait until the kicked refresh is in flight and blocked on the gate.
        let deadline = DispatchTime.now() + DispatchTimeInterval.seconds(5)
        while enumerateCount.pointee < 2 {
            Thread.sleep(forTimeInterval: 0.01)
            if DispatchTime.now() >= deadline { break }
        }
        XCTAssertEqual(enumerateCount.pointee, 2, "inline-fallback kick must be in flight")

        // 3. invalidate() fires while the kick is in flight -> generation bumped.
        provider.invalidateCache()

        // 4. Release: the stale kick completes AFTER the invalidate. Its result must
        //    be discarded and a self-heal refresh with the current generation
        //    re-dispatched (ARCH-1 guarantee).
        gate.signal()
        await provider.waitForAllSpacesRefresh()

        // 5. The self-heal re-kick must have run (enumeration #3). WITHOUT the fix
        //    the stale result is dropped and nothing re-dispatches (count stays 2).
        XCTAssertEqual(enumerateCount.pointee, 3,
                       "stale inline-kick result must be followed by a self-heal refresh")

        // 6. Cache must hold full AX titles WITHOUT another user open, and the open
        //    must be a cache hit (no inline re-enumeration).
        let refreshed = provider.entriesForAllSpaces()
        XCTAssertEqual(refreshed.flatMap(\.entries).first?.windowTitle, "AX Title",
                       "titles must upgrade to AX quality without another user open")
        XCTAssertEqual(enumerateCount.pointee, 3,
                       "post-self-heal open must be a cache hit (no inline re-enumeration)")
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

    // MARK: - Regression tests (round-3 fixes)

    func testDuplicateWindowIDsDoNotCrashInAllSpacesPath() async {
        // Two windows with the same windowID — the pre-resolved map must handle
        // the collision deterministically without crashing (CORR-2/QUAL-2).
        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        let provider = makeProvider(
            bridge: bridge,
            windowInfo: {
                [
                    self.makeWindow(pid: 10, windowID: 1, workspace: 1, isOnScreen: true),
                    self.makeWindow(pid: 20, windowID: 1, workspace: nil, isOnScreen: true)
                ]
            }
        )

        // Must not crash — Dictionary(uniquingKeysWith:) keeps first value
        let groups = provider.entriesForAllSpaces()
        XCTAssertFalse(groups.isEmpty, "groups must be non-empty with duplicate window IDs")

        // The duplicate window ID is kept once in the pre-resolved map;
        // both entries appear in the output (the pipeline preserves all filtered windows).
        let allWindowIDs = groups.flatMap(\.entries).map(\.windowID)
        XCTAssertEqual(Set(allWindowIDs), [1], "duplicate IDs collapse to a single key in grouping")

        await provider.waitForAllSpacesRefresh()
    }

    func testSettingsChangeClearsCGSSpacesCache() async {
        // Verify that changing a space-filtering setting triggers clearSpacesCache()
        // on the injected bridge (not a hardcoded CGSBridge) so stale CGS memoization
        // is not served after invalidation (CORR-1/ARCH-1).
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowMinimizedWindows = false

        let bridge = WindowListProviderMockBridge(
            managedSnapshotValue: makeSnapshot(),
            spacesForWindowValues: [1: [100]]
        )
        let provider = makeProvider(
            settings: settings,
            bridge: bridge,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, isOnScreen: false)] }
        )

        // Initial call — minimized windows hidden
        _ = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        await provider.waitForCurrentSpaceRefresh()
        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        // Change settings — this triggers invalidateCacheIfSettingsChanged() which
        // calls clearSpacesCache() on the injected bridge instance.
        settings.windowSwitcherShowMinimizedWindows = true

        // Next call: cache invalidated (both WindowListCache and CGSSpacesCache cleared)
        let afterChange = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertTrue(afterChange.isEmpty, "settings change invalidates cache")

        // Verify the injected bridge's clearSpacesCache() was called (DI-correct path)
        XCTAssertEqual(bridge.clearSpacesCacheCallCount, 1, "settings change must call clearSpacesCache on the injected bridge")

        await provider.waitForCurrentSpaceRefresh()

        // After refresh: new settings respected with fresh CGS lookups
        let final = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        XCTAssertEqual(final.map(\.windowID), [1], "new settings must be respected after cache clear")
    }
}
