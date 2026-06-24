import AppKit
import Core

@MainActor
final class AppRuntimeCoordinator: AppCoordinating {
    /// Local weak-reference holder, used to break the init-cycle:
    /// `controllers` and `windowManagers` need closures that call back to `self`,
    /// but `self` is not fully initialised until all stored properties are set.
    /// We create the holder first, pass captures of it, then wire it up immediately.
    private final class WeakSelf {
        weak var value: AppRuntimeCoordinator?
    }

    private let services: CompositionServices
    private let registry: any SpaceRegistryProtocol
    private let lifecycleCoordinator: AppLifecycleCoordinator
    let controllers: CompositionControllers
    let windowManagers: CompositionWindowManagers
    private(set) var updateController: (any UpdateControlling)?
    private let setupRequirementsPresenter: SetupRequirementsPresenter

    private let statusBarCoordinator: StatusBarCoordinator
    private let spaceObservationCoordinator: SpaceObservationCoordinator
    private let windowCoordinator: WindowCoordinator
    private let switcherDirector: SwitcherDirector
    private let eventOrchestrationCoordinator: EventOrchestrationCoordinator
    private var lastObservedActiveSpaceID: Int?

    init(
        services: CompositionServices,
        aboutWindowManager: AboutWindowManager,
        updateWindowManager: any UpdateWindowManaging
    ) {
        let weakSelf = WeakSelf()

        self.services = services
        self.registry = services.repository
        self.lifecycleCoordinator = services.lifecycleCoordinator
        self.updateController = nil

        self.controllers = CompositionControllers(
            services: services,
            switchToSpace: { [weakSelf] spaceID in
                Task { [weakSelf] in
                    await weakSelf.value?.spaceObservationCoordinator.performSpaceSwitch(spaceID)
                }
            }
        )

        self.windowManagers = CompositionWindowManagers(
            services: services,
            onAppearanceChange: { [weakSelf] in
                weakSelf.value?.applyAppearanceImmediately()
            }
        )

        self.setupRequirementsPresenter = controllers.setupRequirementsPresenter

        self.statusBarCoordinator = StatusBarCoordinator(
            statusController: controllers.statusController,
            registry: services.repository
        )
        self.spaceObservationCoordinator = SpaceObservationCoordinator(
            registry: services.repository,
            switchSpace: services.switchSpace,
            buildSpaceSnapshot: services.buildSpaceSnapshot,
            switchPresentationHelper: controllers.switchPresentationHelper
        )
        self.windowCoordinator = WindowCoordinator(
            settingsWindowManager: windowManagers.settingsWindowManager,
            aboutWindowManager: aboutWindowManager,
            appearanceManager: services.appearanceManager,
            registry: services.repository,
            refreshSpaces: services.refreshSpaces
        )
        let eventTapProxy = AppEventTapProxy(logger: services.logger)
        self.switcherDirector = SwitcherDirector(
            spaceSwitcherController: controllers.spaceSwitcherController,
            windowSwitcherController: controllers.windowSwitcherController,
            allSpacesWindowSwitcherController: controllers.allSpacesWindowSwitcherController,
            settings: services.settings,
            eventTapProxy: eventTapProxy
        )
        self.eventOrchestrationCoordinator = EventOrchestrationCoordinator(
            hotCornerController: controllers.hotCornerController,
            activationController: controllers.activationController,
            switcherDirector: switcherDirector,
            eventTapProxy: eventTapProxy
        )

        // Wire up the weak reference now that all stored properties are initialised.
        weakSelf.value = self

        windowCoordinator.onSettingsWillOpen = { [weak self] in
            self?.statusBarCoordinator.rebuildSpaceItems()
        }
        windowCoordinator.onSettingsDidClose = { [weak self] in
            guard let self else { return }
            self.eventOrchestrationCoordinator.syncEventDrivenControllers()
            self.statusBarCoordinator.setTitle(self.registry.activeNameSummary())
            self.statusBarCoordinator.rebuildSpaceItems()
        }
    }

    func setUpdateController(_ controller: any UpdateControlling) {
        self.updateController = controller
    }

    var isSettingsOpen: Bool {
        windowCoordinator.isSettingsOpen
    }

    func applicationDidFinishLaunching() {
        updateController?.restoreCachedState()

        // Configure status bar with all menu actions
        statusBarCoordinator.configure(
            onOpenSettings: { [weak self] in self?.windowCoordinator.showSettings() },
            onOpenAbout: { [weak self] in self?.windowCoordinator.showAbout() },
            onCheckForUpdates: { [weak self] in self?.updateController?.performManualCheck() },
            onOpenAvailableUpdate: { [weak self] in self?.updateController?.presentAvailableUpdate() },
            onCopyState: { [weak self] in self?.spaceObservationCoordinator.copySpaceState() },
            onOpenLogs: { [logger = services.logger] in openLogsInFinder(logger: logger) },
            onQuit: { NSApp.terminate(nil) },
            onSelectSpace: { [weak self] id in
                Task { [weak self] in
                    await self?.spaceObservationCoordinator.performSpaceSwitch(id)
                }
            },
            onRenameSpace: { [weak self] id, name in
                guard let self else { return }
                self.services.renameSpace.execute(spaceID: id, name: name)
                self.statusBarCoordinator.setTitle(
                    self.registry.activeSpaceID == id
                        ? Self.normalizedSpaceName(name)
                        : self.registry.activeNameSummary()
                )
            }
        )

        // Bind "settings open" state to observation
        statusBarCoordinator.bindSettingsOpen { [weak self] in
            self?.isSettingsOpen ?? false
        }
        spaceObservationCoordinator.bindSettingsOpen { [weak self] in
            self?.isSettingsOpen ?? false
        }

        // When active space changes → update status bar title and show HUD
        spaceObservationCoordinator.bindActiveSpaceChangedHandler { [weak self] in
            guard let self else { return }
            self.statusBarCoordinator.setTitle(self.registry.activeNameSummary())

            let activeSpaceID = self.registry.activeSpaceID
            if activeSpaceID != self.lastObservedActiveSpaceID {
                self.lastObservedActiveSpaceID = activeSpaceID
                if activeSpaceID != nil {
                    self.controllers.hudController.show(name: self.registry.activeName())
                }
            }
        }

        // When registry changes → rebuild menu
        spaceObservationCoordinator.bindMenuRebuildHandler { [weak self] in
            self?.statusBarCoordinator.rebuildSpaceItems()
        }

        // Initialize HUD dedup to avoid HUD on first registry event at startup
        lastObservedActiveSpaceID = registry.activeSpaceID

        // Start space observation (begins listening to NSWorkspace.activeSpaceDidChangeNotification)
        spaceObservationCoordinator.startObserving()

        // Run lifecycle coordinator - sets activation policy, starts timers, checks setup requirements
        lifecycleCoordinator.applicationDidFinishLaunching(
            isSettingsOpen: { [weak self] in self?.isSettingsOpen ?? false },
            refreshSpacesSoon: { [weak self] in self?.services.refreshSpaces.refreshWithRetry() },
            refreshSpacesAsync: { [weak self] in self?.services.refreshSpaces.refreshAsync() },
            rebuildSpaceItems: { [weak self] in
                self?.statusBarCoordinator.rebuildSpaceItems()
            },
            startEventDrivenControllers: { [weak self] in
                self?.eventOrchestrationCoordinator.startEventDrivenControllers()
            },
            presentSetupRequirementsWarning: { [weak self] in
                self?.setupRequirementsPresenter.presentSetupRequirementsWarning()
            }
        )
        updateController?.scheduleAutomaticCheck()
    }

    func applicationWillTerminate() {
        lifecycleCoordinator.applicationWillTerminate { [weak self] in
            self?.eventOrchestrationCoordinator.stopEventDrivenControllers()
        }
        spaceObservationCoordinator.stopObserving()
    }

    func handleIncomingURL(_ url: URL) {
        eventOrchestrationCoordinator.handleIncomingURL(url)
    }

    func applyAppearanceImmediately() {
        windowCoordinator.applyAppearanceImmediately()
        statusBarCoordinator.applyCurrentAppearance()
    }

    func performSpaceSwitch(_ spaceID: Int) async {
        await spaceObservationCoordinator.performSpaceSwitch(spaceID)
    }

    private static func normalizedSpaceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SpaceDisplayNameProvider.defaultUnnamedName : trimmed
    }
}
