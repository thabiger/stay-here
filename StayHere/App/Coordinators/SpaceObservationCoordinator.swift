import AppKit
import Combine
import Core

@MainActor
final class SpaceObservationCoordinator {
    private let registry: SpaceRegistry
    private let switchSpace: SwitchSpaceUseCase
    private let buildSpaceSnapshot: BuildSpaceSnapshotUseCase
    private let hudController: HUDController
    private let switchPresentationHelper: SpaceSwitchPresentationHelper

    private var cancellables: Set<AnyCancellable> = []
    private var activeSpaceObserver: NSObjectProtocol?
    private var lastObservedActiveSpaceID: Int?
    private var isSettingsOpen: () -> Bool = { false }
    private var onActiveSpaceChanged: (() -> Void)?
    private var onScheduleMenuRebuild: (() -> Void)?

    init(
        registry: SpaceRegistry,
        switchSpace: SwitchSpaceUseCase,
        buildSpaceSnapshot: BuildSpaceSnapshotUseCase,
        hudController: HUDController,
        switchPresentationHelper: SpaceSwitchPresentationHelper
    ) {
        self.registry = registry
        self.switchSpace = switchSpace
        self.buildSpaceSnapshot = buildSpaceSnapshot
        self.hudController = hudController
        self.switchPresentationHelper = switchPresentationHelper
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

    func startObserving() {
        bindRegistry()
        observeActiveSpaceChanges()
    }

    func performSpaceSwitch(_ spaceID: Int) {
        let result = switchSpace.execute(spaceID)
        switchPresentationHelper.presentWarning(for: result)
    }

    func copySpaceState() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(buildSpaceSnapshot.execute(), forType: .string)
    }

    private func bindRegistry() {
        lastObservedActiveSpaceID = registry.activeSpaceID

        registry.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isSettingsOpen() else { return }
                let activeSpaceID = self.registry.activeSpaceID
                self.onActiveSpaceChanged?()
                if activeSpaceID != self.lastObservedActiveSpaceID {
                    self.lastObservedActiveSpaceID = activeSpaceID
                    if activeSpaceID != nil {
                        self.hudController.show(name: self.registry.activeName())
                    }
                }
                self.onScheduleMenuRebuild?()
            }
            .store(in: &cancellables)
    }

    private func observeActiveSpaceChanges() {
        guard activeSpaceObserver == nil else { return }
        activeSpaceObserver = NotificationCenter.default.addObserver(
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
    }

    func stopObserving() {
        if let observer = activeSpaceObserver {
            NotificationCenter.default.removeObserver(observer)
            activeSpaceObserver = nil
        }
    }
}
