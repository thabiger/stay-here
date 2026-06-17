import AppKit
import Core
import CoreGraphics
import XCTest
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

private final class FakeWindowListSettings: SettingsRepository {
    var appearanceMode: AppearanceMode = .system
    var diagnosticsEnabled: Bool = false
    var automaticUpdateChecksEnabled: Bool = true
    var spaceSwitcherEnabled: Bool = true
    var spaceSwitcherShortcutText: String = "command+tab"
    var windowSwitcherEnabled: Bool = true
    var windowSwitcherShortcutText: String = "command+`"
    var windowSwitcherTitleFormat: WindowSwitcherTitleFormat = .appNameOnly
    var windowSwitcherShowMinimizedWindows: Bool = false
    var windowSwitcherShowHiddenWindows: Bool = false
    var hotCornerTopLeftAction: HotCornerAction = .none
    var hotCornerTopRightAction: HotCornerAction = .none
    var hotCornerBottomLeftAction: HotCornerAction = .none
    var hotCornerBottomRightAction: HotCornerAction = .none
    var hudDisplayDuration: TimeInterval = 1.8
    var activationDockClickInterceptionEnabled: Bool = true
    var activationSingleWindowAppBundleIDs: [String] = []
}

final class WindowListProviderTests: XCTestCase {
    private func makeRegistry(bridge: WindowListProviderMockBridge) -> SpaceRegistry {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowListProviderTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        return SpaceRegistry(store: store, cgsBridge: bridge)
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

    func testFiltersOutNonLayerZeroWindows() {
        let provider = makeProvider {
            [
                self.makeWindow(pid: 10, windowID: 1, layer: 0),
                self.makeWindow(pid: 10, windowID: 2, layer: 3)
            ]
        }

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))

        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testRespectsWorkspaceMatchWhenDesktopNumberExists() {
        let provider = makeProvider {
            [
                self.makeWindow(pid: 10, windowID: 1, workspace: 1),
                self.makeWindow(pid: 10, windowID: 2, workspace: 2)
            ]
        }

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))

        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testFallsBackToSpacesForWindowWhenWorkspaceIsMissing() {
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

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))

        XCTAssertEqual(entries.map { $0.windowID }, [1])
    }

    func testHonorsHiddenWindowSetting() {
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowHiddenWindows = false
        let hiddenApp = FakeWindowListApplication(isHidden: true, localizedName: "Notes", bundleURL: nil)
        let provider = makeProvider(
            settings: settings,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1)] },
            runningApplications: [10: hiddenApp]
        )

        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        settings.windowSwitcherShowHiddenWindows = true

        XCTAssertEqual(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).map { $0.windowID }, [1])
    }

    func testHonorsMinimizedWindowSetting() {
        let settings = FakeWindowListSettings()
        settings.windowSwitcherShowMinimizedWindows = false
        let provider = makeProvider(
            settings: settings,
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, isOnScreen: false)] }
        )

        XCTAssertTrue(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).isEmpty)

        settings.windowSwitcherShowMinimizedWindows = true

        XCTAssertEqual(provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1)).map { $0.windowID }, [1])
    }

    func testUsesAccessibilityTitleFallbackWhenWindowTitleIsEmpty() {
        let provider = makeProvider(
            windowInfo: { [self.makeWindow(pid: 10, windowID: 1, title: "   ")] },
            accessibilityTitles: [10: [1: "Recovered Title"]]
        )

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))

        XCTAssertEqual(entries.first?.windowTitle, "Recovered Title")
    }

    func testReturnsStableMetadataForSnapshotBuilding() throws {
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

        let entries = provider.entries(in: WindowSpaceContext(spaceID: 100, desktopNumber: 1))
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.pid, 22)
        XCTAssertEqual(entry.appName, "Calendar")
        XCTAssertEqual(entry.windowTitle, "Today")
        XCTAssertTrue(entry.icon === icon)
    }
}
