import AppKit
import SwiftUI
import Combine
import Core
import Activation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: SettingsRepository
    private let cgsBridge: any CGSBridgeProtocol
    private let appearanceManager: AppearanceManager
    private let lifecycleCoordinator: AppLifecycleCoordinator
    private lazy var registry = SpaceRegistry(cgsBridge: cgsBridge)
    private let statusController: StatusBarController
    private let hudController: HUDController
    private lazy var settingsWindowManager = SettingsWindowManager(
        settings: settings,
        appearanceManager: appearanceManager,
        onAppearanceChange: { [weak self] in
            self?.applyAppearanceImmediately()
        },
        onWillOpen: { [weak self] in
            self?.pauseBackgroundUpdates()
        },
        onDidClose: { [weak self] in
            self?.settingsWindowDidClose()
        }
    )
    private lazy var switchPresentationHelper = SpaceSwitchPresentationHelper(
        appearanceManager: appearanceManager
    )
    private lazy var activationController = ActivationController(
        settings: settings,
        windowIndex: WindowIndex(cgsBridge: cgsBridge),
        currentSpaceID: { [weak self] in
            self?.registry.activeSpaceID
        },
        activeSpaceIDs: { [weak self] in
            guard let id = self?.registry.activeSpaceID else { return [] }
            return Set([id])
        },
        switchToSpace: { [weak self] spaceID in
            self?.performSpaceSwitch(spaceID)
        },
        onShowSingleWindowHint: { [weak self] message in
            self?.hudController.show(message: message)
        }
    )
    private lazy var spaceSwitcherController = SpaceSwitcherController(
        settings: settings,
        registry: registry,
        switchToSpace: { [weak self] spaceID in
            self?.performSpaceSwitch(spaceID)
        }
    )
    private lazy var windowSwitcherController = WindowSwitcherController(
        settings: settings,
        registry: registry,
        cgsBridge: cgsBridge
    )
    private var cancellables: Set<AnyCancellable> = []
    private var menuRebuildWorkItem: DispatchWorkItem?

    init(
        settings: SettingsRepository = UserDefaultsSettingsRepository(),
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live
    ) {
        self.settings = settings
        self.cgsBridge = cgsBridge
        self.appearanceManager = AppearanceManager(settings: settings)
        self.lifecycleCoordinator = AppLifecycleCoordinator(appearanceManager: self.appearanceManager)
        self.statusController = StatusBarController(settings: settings, appearanceManager: appearanceManager)
        self.hudController = HUDController(settings: settings, appearanceManager: appearanceManager)
        super.init()
    }

    var isSettingsOpen: Bool { settingsWindowManager.isOpen }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.configure(
            onOpenSettings: { [weak self] in self?.showSettings() },
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

        registry.$activeSpaceID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self, !self.isSettingsOpen else { return }
                let title = self.registry.activeNameSummary()
                self.statusController.setTitle(title)
                if id != nil {
                    self.hudController.show(name: self.registry.activeName())
                }
            }
            .store(in: &cancellables)

        registry.$labels.combineLatest(registry.$spaces)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.scheduleMenuRebuild()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        lifecycleCoordinator.applicationDidFinishLaunching(
            isSettingsOpen: { [weak self] in self?.isSettingsOpen ?? false },
            refreshSpacesSoon: { [weak self] in self?.registry.refreshSpacesSoon() },
            refreshSpacesAsync: { [weak self] in self?.registry.refreshSpacesAsync() },
            rebuildSpaceItems: { [weak self] in
                guard let self else { return }
                self.statusController.rebuildSpaceItems(registry: self.registry)
            },
            startEventDrivenControllers: { [weak self] in self?.startEventDrivenControllers() },
            presentSetupRequirementsWarning: { [weak self] in self?.presentSetupRequirementsWarning() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleCoordinator.applicationWillTerminate { [weak self] in
            self?.spaceSwitcherController.stop()
            self?.windowSwitcherController.stop()
            self?.activationController.stop()
        }
    }

    @objc private func activeSpaceChanged() {
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

    private func pauseBackgroundUpdates() {
        menuRebuildWorkItem?.cancel()
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

    private static func normalizedSpaceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed space" : trimmed
    }

    private func settingsWindowDidClose() {
        applyAppearanceImmediately()
        syncEventDrivenControllers()
        statusController.setTitle(registry.activeNameSummary())
        statusController.rebuildSpaceItems(registry: registry)
    }

    private func applyAppearanceImmediately() {
        appearanceManager.applyCurrentMode()
        statusController.applyCurrentAppearance()
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

    private func performSpaceSwitch(_ spaceID: Int) {
        let result = registry.switchToSpace(spaceID)
        switchPresentationHelper.presentWarning(for: result)
    }

    private func presentSetupRequirementsWarning() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Set up StayHere before you start"
            alert.informativeText = """
            StayHere runs from the menu bar and helps you name Spaces, switch between them, pick windows on the current Space, and keep Dock clicks on the desktop you are using.

            To do that, macOS needs to allow a few things:

            • Accessibility lets StayHere focus apps, read Dock state, and apply space-related behavior.
            • Control+<Number> under Mission Control are the built-in shortcuts StayHere relies on for desktop switching (this one is under Settings -> Keyboard -> Keyboard Shortcuts -> Mission Control).

            Use the checklist below. A green check means that item is ready; click any missing item to jump to the right System Settings pane, make the change, then return here and click Reload to relaunch StayHere. StayHere will start once every required item is checked.
            """
            alert.addButton(withTitle: "OK")
            //alert.addButton(withTitle: "Quit")

            let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            let supplementaryText = NSMutableAttributedString(
                string: "StayHere goal is to deliver a focus-first experience to your workflow. Therefore we encourage you to run it with additional settings:\n",
                attributes: [.font: boldFont]
            )
            supplementaryText.append(NSAttributedString(
                string: """
                • Settings -> Desktop & Dock -> Automatically rearrange Spaces based on most recent use -> Off
                • Settings -> Desktop & Dock -> When switching to an application, switch to a Space with open windows for the application -> Off (prevents teleporting to other spaces through Spotlight)
                • Settings -> Desktop & Dock -> Group windows by application -> On
                • Settings -> Desktop & Dock -> Displays have separate Spaces -> Off (it messes with spaces location across displays, when they disconnect)
                • Settings -> Desktop & Dock -> Show suggested and recent apps in Dock -> Off (you should only see what you need to make your work in your space done)

                Please click OK when you've made the changes and start the app again.
                """,
                attributes: [.font: bodyFont]
            ))

            let checklist = SetupChecklistAccessoryView(
                status: StayHereSetupStatus.current(),
                supplementaryText: supplementaryText
            )
            alert.accessoryView = checklist
            self.appearanceManager.applyCurrentMode(to: [alert.window])
            self.switchPresentationHelper.ensureAlertWidth(alert, minimumWidth: 720)

            checklist.refresh(with: StayHereSetupStatus.current())
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
                return
            }
            //self.reloadApplication()
        }
    }

    private func reloadApplication() {
        let bundleURL = Bundle.main.bundleURL
        Logger.shared.info("reload requested")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if error != nil {
                Logger.shared.error("failed to reload app after setup changes")
                Logger.shared.flush()
                self.showReloadFailureAlert()
                return
            }
            Logger.shared.info("reload launch request succeeded")
            Logger.shared.flush()
            NSApp.terminate(nil)
        }
    }

    private func showReloadFailureAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "StayHere couldn't reload"
            alert.informativeText = "Quit and reopen StayHere to apply the macOS permission changes."
            alert.addButton(withTitle: "OK")
            self.appearanceManager.applyCurrentMode(to: [alert.window])
            self.switchPresentationHelper.ensureAlertWidth(alert, minimumWidth: 420)
            _ = alert.runModal()
        }
    }
}
