import XCTest
import AppKit
import SwiftUI
import Core
@testable import StayHereApp

private final class LocalMockCGSBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int? = 100
    var managedSnapshotValue = CGSBridge.ManagedSnapshot(
        spaces: [],
        activeByDisplay: [:],
        orderedIDsByDisplay: [:]
    )

    func activeSpaceID() -> Int? { activeSpaceIDValue }
    func managedSnapshot() -> CGSBridge.ManagedSnapshot { managedSnapshotValue }
    func managedSpaces() -> [SpaceIdentity] { managedSnapshotValue.spaces }
    func switchByDesktopShortcut(index: Int) -> Bool { true }
    func spacesForWindow(windowID: Int) -> [Int] { [] }
}

@MainActor
final class SwitcherPanelReleaseTests: XCTestCase {
    private func makeSpaceController() -> SpaceSwitcherController {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitcherPanelReleaseTests-Space")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let bridge = LocalMockCGSBridge()
        let registry = SpaceRegistry(store: store, cgsBridge: bridge, logger: NoOpLogger())
        return SpaceSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            switchToSpace: { _ in }
        )
    }

    private func makeWindowController() -> WindowSwitcherController {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitcherPanelReleaseTests-Window")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("spaces.json")
        let store = SpaceStore(fileURL: fileURL)
        let bridge = LocalMockCGSBridge()
        let repository = SpaceStateManager(store: store, cgsBridge: bridge, logger: NoOpLogger())
        let registry = SpaceRegistry(repository: repository)
        let refreshSpaces = RefreshSpacesUseCase(repository: repository, logger: NoOpLogger())
        let switchSpace = SwitchSpaceUseCase(cgsBridge: bridge, repository: repository, refreshUseCase: refreshSpaces, logger: NoOpLogger())
        let listProvider = WindowListProvider(
            registry: registry,
            cgsBridge: bridge,
            settings: UserDefaultsSettingsRepository(),
            windowInfoProvider: { nil },
            runningApplicationProvider: { _ in nil },
            accessibilityWindowTitlesProvider: { _ in [:] },
            focusedWindowIDProvider: { nil },
            iconProvider: { _ in NSImage(size: NSSize(width: 18, height: 18)) }
        )
        let windowSwitchUseCase = WindowSwitchUseCase(dependencies: .init(
            cgsBridge: bridge,
            listProvider: listProvider,
            switchSpace: switchSpace,
            refreshSpaces: refreshSpaces,
            focusService: WindowFocusService()
        ))
        return WindowSwitcherController(
            settings: UserDefaultsSettingsRepository(),
            registry: registry,
            mode: .currentSpace,
            windowSwitchUseCase: windowSwitchUseCase,
            cgsBridge: bridge,
            listProvider: listProvider
        )
    }

    private func makeSpacePanel() -> (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = SpaceSwitcherView(
            snapshot: SpaceSwitcherSnapshot(items: [], title: ""),
            onSelect: { _ in }
        )
        let hosting = NSHostingController(rootView: view)
        return (window: panel, hosting: hosting)
    }

    private func makeWindowPanel() -> (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = WindowSwitcherView(
            snapshot: WindowSwitcherSnapshot(
                spaceGroups: [],
                title: "",
                subtitle: "",
                emptyMessage: "",
                iconName: "macwindow",
                showSpaceLabels: false
            ),
            onSelect: { _ in }
        )
        let hosting = NSHostingController(rootView: view)
        return (window: panel, hosting: hosting)
    }

    /// M3: SpaceSwitcherController.stop() must release the NSPanel and
    /// NSHostingController (panelPair = nil) so they aren't retained when
    /// the user disables the feature.
    func testSpaceSwitcherStopReleasesPanel() {
        let controller = makeSpaceController()
        controller.panelPair = makeSpacePanel()
        XCTAssertNotNil(controller.panelPair)

        controller.stop()

        XCTAssertNil(controller.panelPair, "panelPair must be released on stop()")
    }

    /// M3: WindowSwitcherController.stop() must release the NSPanel and
    /// NSHostingController (panelPair = nil).
    func testWindowSwitcherStopReleasesPanel() {
        let controller = makeWindowController()
        controller.panelPair = makeWindowPanel()
        XCTAssertNotNil(controller.panelPair)

        controller.stop()

        XCTAssertNil(controller.panelPair, "panelPair must be released on stop()")
    }

    /// M3 follow-up: calling stop() multiple times is safe and idempotent.
    func testSpaceSwitcherStopIsIdempotent() {
        let controller = makeSpaceController()
        controller.panelPair = makeSpacePanel()

        controller.stop()
        controller.stop()
        controller.stop()

        XCTAssertNil(controller.panelPair)
    }

    func testWindowSwitcherStopIsIdempotent() {
        let controller = makeWindowController()
        controller.panelPair = makeWindowPanel()

        controller.stop()
        controller.stop()
        controller.stop()

        XCTAssertNil(controller.panelPair)
    }
}
