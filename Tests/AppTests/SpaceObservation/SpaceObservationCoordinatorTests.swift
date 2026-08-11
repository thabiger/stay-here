import AppKit
import Core
import TestHelpers
import XCTest
@testable import StayHereApp

@MainActor
final class SpaceObservationCoordinatorTests: XCTestCase {
    private final class StubCGSBridge: CGSBridgeProtocol {
        var activeSpaceIDValue: Int?
        var managedSnapshotValue: CGSBridge.ManagedSnapshot

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
        func spacesForWindow(windowID: Int) -> [Int] { [] }
    }

    /// Builds a coordinator over a real registry so the wiring matches production.
    /// The notification center is injectable: tests pass an isolated center to
    /// prove the center contract without touching the real workspace center.
    private func makeCoordinator(
        notificationCenter: NotificationCenter
    ) -> (coordinator: SpaceObservationCoordinator, stateStore: SpaceStateStore) {
        let bridge = StubCGSBridge()
        let stateStore = SpaceStateStore()
        let pair = SpaceStateManagerFactory.makePair(cgsBridge: bridge, stateStore: stateStore)
        let refreshUseCase = RefreshSpacesUseCase(repository: pair.manager, logger: NoOpLogger())
        let switchUseCase = SwitchSpaceUseCase(
            cgsBridge: bridge,
            repository: pair.queryService,
            refreshUseCase: refreshUseCase,
            logger: NoOpLogger()
        )
        let snapshotUseCase = BuildSpaceSnapshotUseCase(builder: pair.queryService)
        let helper = SpaceSwitchPresentationHelper(
            appearanceManager: AppearanceManager(settings: UserDefaultsSettingsRepository()),
            activateApp: {},
            openURL: { _ in false },
            openSystemSettingsApp: {}
        )
        let coordinator = SpaceObservationCoordinator(
            registry: pair.queryService,
            switchSpace: switchUseCase,
            buildSpaceSnapshot: snapshotUseCase,
            switchPresentationHelper: helper,
            notificationCenter: notificationCenter
        )
        return (coordinator, stateStore)
    }

    private func postActiveSpaceChange(on center: NotificationCenter) {
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
    }

    // MARK: - Notification center contract

    /// Regression: the original implementation registered on NotificationCenter.default,
    /// which can never receive NSWorkspace.activeSpaceDidChangeNotification. Apple's
    /// docs: "To receive this notification, use NSWorkspace.notificationCenter to
    /// register for it. If you use a different notification center to register, you
    /// won't receive the notification." A coordinator wired to the default center must
    /// never fire, even if the real system notification is posted on the workspace center.
    func testCoordinatorOnDefaultCenterNeverReceivesWorkspaceNotification() {
        let (coordinator, _) = makeCoordinator(notificationCenter: NotificationCenter.default)
        var activeChanged = false
        coordinator.bindActiveSpaceChangedHandler { activeChanged = true }
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        postActiveSpaceChange(on: NSWorkspace.shared.notificationCenter)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(activeChanged)
    }

    func testNotificationOnWorkspaceCenterTriggersActiveSpaceChangedAndRefreshHandlers() {
        let center = NotificationCenter()
        let (coordinator, _) = makeCoordinator(notificationCenter: center)
        let activeChanged = expectation(description: "active space changed handler")
        let refreshCalled = expectation(description: "refresh handler")
        coordinator.bindActiveSpaceChangedHandler { activeChanged.fulfill() }
        coordinator.bindRefreshSpacesHandler { refreshCalled.fulfill() }
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        postActiveSpaceChange(on: center)

        wait(for: [activeChanged, refreshCalled], timeout: 1)
    }

    func testDefaultInitUsesRealWorkspaceNotificationCenter() {
        let (coordinator, _) = makeCoordinator(notificationCenter: NSWorkspace.shared.notificationCenter)
        let activeChanged = expectation(description: "active space changed handler")
        coordinator.bindActiveSpaceChangedHandler { activeChanged.fulfill() }
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        postActiveSpaceChange(on: NSWorkspace.shared.notificationCenter)

        wait(for: [activeChanged], timeout: 1)
    }

    // MARK: - Observer lifecycle

    func testStopObservingStopsHandlerDelivery() {
        let center = NotificationCenter()
        let (coordinator, _) = makeCoordinator(notificationCenter: center)
        var activeChangedCount = 0
        coordinator.bindActiveSpaceChangedHandler { activeChangedCount += 1 }
        coordinator.startObserving()
        coordinator.stopObserving()

        postActiveSpaceChange(on: center)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(activeChangedCount, 0)
    }

    // MARK: - Gating

    func testHandlersSkippedWhileSettingsOpen() {
        let center = NotificationCenter()
        let (coordinator, _) = makeCoordinator(notificationCenter: center)
        var activeChanged = false
        var refreshCalled = false
        coordinator.bindSettingsOpen { true }
        coordinator.bindActiveSpaceChangedHandler { activeChanged = true }
        coordinator.bindRefreshSpacesHandler { refreshCalled = true }
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        postActiveSpaceChange(on: center)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(activeChanged)
        XCTAssertFalse(refreshCalled)
    }

    // MARK: - Registry-driven updates

    /// The HUD/title path has two ticks: the notification tick (registry still
    /// stale → deduped) and the registry-change tick (refresh landed → HUD shows).
    /// This guards the second tick: a registry state change must re-fire the
    /// active-space handler via objectWillChange.
    func testRegistryStateChangeTriggersActiveSpaceChangedHandler() {
        let (coordinator, stateStore) = makeCoordinator(notificationCenter: NotificationCenter())
        let activeChanged = expectation(description: "active space changed handler")
        coordinator.bindActiveSpaceChangedHandler { activeChanged.fulfill() }
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        stateStore.applyDerivedState(
            SpaceRegistryDerivedState(
                spaces: [],
                activeSpaceID: 42,
                nativeOrderByDisplay: [:],
                desktopNumberBySpaceID: [:]
            )
        )

        wait(for: [activeChanged], timeout: 1)
    }
}
