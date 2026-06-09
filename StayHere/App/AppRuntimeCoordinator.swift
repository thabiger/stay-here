import AppKit
import Combine
import Core
import Activation

@MainActor
final class AppRuntimeCoordinator: AppCoordinating {
    private let settings: SettingsRepository
    private let appearanceManager: AppearanceManager
    private let lifecycleCoordinator: AppLifecycleCoordinator
    private let registry: SpaceRegistry
    private let statusController: StatusBarController
    private let updateController: any UpdateControlling
    private let hudController: HUDController
    private let settingsWindowManager: SettingsWindowManager
    private let aboutWindowManager: AboutWindowManager
    private let activationController: ActivationController
    private let spaceSwitcherController: SpaceSwitcherController
    private let windowSwitcherController: WindowSwitcherController
    private let switchPresentationHelper: SpaceSwitchPresentationHelper
    private let setupRequirementsPresenter: SetupRequirementsPresenter

    private var cancellables: Set<AnyCancellable> = []
    private var menuRebuildWorkItem: DispatchWorkItem?
    private var activeSpaceObserver: NSObjectProtocol?
    private var lastObservedActiveSpaceID: Int?

    init(
        settings: SettingsRepository,
        appearanceManager: AppearanceManager,
        lifecycleCoordinator: AppLifecycleCoordinator,
        registry: SpaceRegistry,
        statusController: StatusBarController,
        updateController: any UpdateControlling,
        hudController: HUDController,
        settingsWindowManager: SettingsWindowManager,
        aboutWindowManager: AboutWindowManager,
        activationController: ActivationController,
        spaceSwitcherController: SpaceSwitcherController,
        windowSwitcherController: WindowSwitcherController,
        switchPresentationHelper: SpaceSwitchPresentationHelper,
        setupRequirementsPresenter: SetupRequirementsPresenter
    ) {
        self.settings = settings
        self.appearanceManager = appearanceManager
        self.lifecycleCoordinator = lifecycleCoordinator
        self.registry = registry
        self.statusController = statusController
        self.updateController = updateController
        self.hudController = hudController
        self.settingsWindowManager = settingsWindowManager
        self.aboutWindowManager = aboutWindowManager
        self.activationController = activationController
        self.spaceSwitcherController = spaceSwitcherController
        self.windowSwitcherController = windowSwitcherController
        self.switchPresentationHelper = switchPresentationHelper
        self.setupRequirementsPresenter = setupRequirementsPresenter
    }

    var isSettingsOpen: Bool { settingsWindowManager.isOpen }

    func applicationDidFinishLaunching() {
        configureStatusController()
        updateController.restoreCachedState()
        bindRegistry()
        observeActiveSpaceChanges()

        lifecycleCoordinator.applicationDidFinishLaunching(
            isSettingsOpen: { [weak self] in self?.isSettingsOpen ?? false },
            refreshSpacesSoon: { [weak self] in self?.registry.refreshSpacesSoon() },
            refreshSpacesAsync: { [weak self] in self?.registry.refreshSpacesAsync() },
            rebuildSpaceItems: { [weak self] in
                guard let self else { return }
                self.statusController.rebuildSpaceItems(registry: self.registry)
            },
            startEventDrivenControllers: { [weak self] in self?.startEventDrivenControllers() },
            presentSetupRequirementsWarning: { [weak self] in
                self?.setupRequirementsPresenter.presentSetupRequirementsWarning()
            }
        )
        updateController.scheduleAutomaticCheck()
    }

    func applicationWillTerminate() {
        lifecycleCoordinator.applicationWillTerminate { [weak self] in
            self?.stopEventDrivenControllers()
        }
        if let activeSpaceObserver {
            NotificationCenter.default.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
    }

    func applyAppearanceImmediately() {
        appearanceManager.applyCurrentMode()
        statusController.applyCurrentAppearance()
    }

    func pauseBackgroundUpdates() {
        menuRebuildWorkItem?.cancel()
    }

    func settingsWindowDidClose() {
        applyAppearanceImmediately()
        syncEventDrivenControllers()
        statusController.setTitle(registry.activeNameSummary())
        statusController.rebuildSpaceItems(registry: registry)
    }

    func performSpaceSwitch(_ spaceID: Int) {
        let result = registry.switchToSpace(spaceID)
        switchPresentationHelper.presentWarning(for: result)
    }

    private func configureStatusController() {
        statusController.configure(
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenAbout: { [weak self] in self?.showAbout() },
            onCheckForUpdates: { [weak self] in self?.updateController.performManualCheck() },
            onOpenAvailableUpdate: { [weak self] in self?.updateController.presentAvailableUpdate() },
            onCopyState: { [weak self] in self?.copySpaceState() },
            onOpenLogs: {
                Logger.shared.openLogsInFinder()
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onSelectSpace: { [weak self] id in
                self?.performSpaceSwitch(id)
            },
            onRenameSpace: { [weak self] id, name in
                guard let self else { return }
                self.registry.rename(spaceID: id, name: name)
                if self.registry.activeSpaceID == id {
                    self.statusController.setTitle(Self.normalizedSpaceName(name))
                } else {
                    self.statusController.setTitle(self.registry.activeNameSummary())
                }
            }
        )
    }

    private func bindRegistry() {
        lastObservedActiveSpaceID = registry.activeSpaceID

        registry.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isSettingsOpen else { return }
                let activeSpaceID = self.registry.activeSpaceID
                self.statusController.setTitle(self.registry.activeNameSummary())
                if activeSpaceID != self.lastObservedActiveSpaceID {
                    self.lastObservedActiveSpaceID = activeSpaceID
                    if activeSpaceID != nil {
                        self.hudController.show(name: self.registry.activeName())
                    }
                }
                self.scheduleMenuRebuild()
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
        lifecycleCoordinator.handleActiveSpaceChanged(
            isSettingsOpen: isSettingsOpen,
            refreshSpacesSoon: { [weak self] in self?.registry.refreshSpacesSoon() }
        )
    }

    private func showSettings() {
        settingsWindowManager.showSettings(refreshRegistry: { [weak self] in
            self?.registry.refreshSpaces()
        })
    }

    private func showAbout() {
        aboutWindowManager.showAbout()
    }

    private func scheduleMenuRebuild() {
        guard !isSettingsOpen, !statusController.isEditingSpaceName else { return }
        menuRebuildWorkItem?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.isSettingsOpen, !self.statusController.isEditingSpaceName else { return }
            self.statusController.rebuildSpaceItems(registry: self.registry)
        }
        menuRebuildWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    private func copySpaceState() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(registry.snapshotJSON(), forType: .string)
    }

    private func startEventDrivenControllers() {
        activationController.start()
        syncEventDrivenControllers()
    }

    private func stopEventDrivenControllers() {
        spaceSwitcherController.stop()
        windowSwitcherController.stop()
        activationController.stop()
    }

    private func syncEventDrivenControllers() {
        if settings.spaceSwitcherEnabled {
            spaceSwitcherController.start()
        } else {
            spaceSwitcherController.stop()
        }

        if settings.windowSwitcherEnabled {
            windowSwitcherController.start()
        } else {
            windowSwitcherController.stop()
        }
    }

    private static func normalizedSpaceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed space" : trimmed
    }
}
