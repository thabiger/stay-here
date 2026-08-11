import AppKit
import Combine
import Core

@MainActor
final class SpaceObservationCoordinator {
    private let registry: any SpaceRegistryProtocol
    private let switchSpace: SwitchSpaceUseCase
    private let buildSpaceSnapshot: BuildSpaceSnapshotUseCase
    private let switchPresentationHelper: SpaceSwitchPresentationHelper
    private let notificationCenter: NotificationCenter

    private var cancellables: Set<AnyCancellable> = []
    private var activeSpaceObserver: NSObjectProtocol?
    private var isSettingsOpen: () -> Bool = { false }
    private var onActiveSpaceChanged: (() -> Void)?
    private var onScheduleMenuRebuild: (() -> Void)?
    private var onRefreshSpaces: (() -> Void)?

    init(
        registry: any SpaceRegistryProtocol,
        switchSpace: SwitchSpaceUseCase,
        buildSpaceSnapshot: BuildSpaceSnapshotUseCase,
        switchPresentationHelper: SpaceSwitchPresentationHelper,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.registry = registry
        self.switchSpace = switchSpace
        self.buildSpaceSnapshot = buildSpaceSnapshot
        self.switchPresentationHelper = switchPresentationHelper
        self.notificationCenter = notificationCenter
    }

    func bindSettingsOpen(_ isSettingsOpen: @escaping () -> Bool) {
        self.isSettingsOpen = isSettingsOpen
    }

    func bindActiveSpaceChangedHandler(_ handler: @escaping () -> Void) {
        self.onActiveSpaceChanged = handler
    }

    func bindMenuRebuildHandler(_ handler: @escaping () -> Void) {
        self.onScheduleMenuRebuild = handler
    }

    func bindRefreshSpacesHandler(_ handler: @escaping () -> Void) {
        self.onRefreshSpaces = handler
    }

    func startObserving() {
        bindRegistry()
        observeActiveSpaceChanges()
    }

    func performSpaceSwitch(_ spaceID: Int) async {
        let result = await switchSpace.execute(spaceID)
        switchPresentationHelper.presentWarning(for: result)
    }

    func copySpaceState() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(buildSpaceSnapshot.execute(), forType: .string)
    }

    private func bindRegistry() {
        registry.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isSettingsOpen() else { return }
                self.onActiveSpaceChanged?()
                self.onScheduleMenuRebuild?()
            }
            .store(in: &cancellables)
    }

    private func observeActiveSpaceChanges() {
        guard activeSpaceObserver == nil else { return }
        // IMPORTANT: NSWorkspace.activeSpaceDidChangeNotification is delivered ONLY on
        // NSWorkspace.shared.notificationCenter — NOT on NotificationCenter.default.
        // Apple: "To receive this notification, use NSWorkspace.notificationCenter to
        // register for it. If you use a different notification center to register, you
        // won't receive the notification." Registering on the default center silently
        // breaks all native space-switch detection (HUD, bar title, refresh). The
        // center is injectable so tests can assert this contract.
        activeSpaceObserver = notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActiveSpaceChanged()
            }
        }
    }

    private func handleActiveSpaceChanged() {
        guard !isSettingsOpen() else { return }
        onActiveSpaceChanged?()
        onRefreshSpaces?()
    }

    func stopObserving() {
        if let observer = activeSpaceObserver {
            notificationCenter.removeObserver(observer)
            activeSpaceObserver = nil
        }
    }
}
