import AppKit
import SwiftUI
import Combine
import Core
import Activation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = SpaceRegistry()
    private let statusController = StatusBarController()
    private let hudController = HUDController()
    private lazy var activationController = ActivationController(currentSpaceID: { [weak self] in
        self?.registry.activeSpaceID
    }, activeSpaceIDs: { [weak self] in
        guard let id = self?.registry.activeSpaceID else { return [] }
        return Set([id])
    }, switchToSpace: { [weak self] spaceID in
        self?.registry.switchToSpace(spaceID)
    }, onShowSingleWindowHint: { [weak self] message in
        self?.hudController.show(message: message)
    })
    private lazy var spaceSwitcherController = SpaceSwitcherController(
        registry: registry,
        switchToSpace: { [weak self] spaceID in
            self?.registry.switchToSpace(spaceID)
        }
    )
    private lazy var windowSwitcherController = WindowSwitcherController(
        registry: registry
    )
    private var settingsWindow: NSWindow?
    private var settingsHostingController: NSHostingController<SettingsView>?
    private var settingsCoordinator: SettingsCoordinator?
    private var cancellables: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var menuRebuildWorkItem: DispatchWorkItem?

    var isSettingsOpen: Bool { settingsWindow != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceManager.applyCurrentMode()

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
                self?.registry.switchToSpace(id)
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

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isSettingsOpen else { return }
            self.registry.refreshSpacesSoon()
        }

        registry.refreshSpacesAsync()
        statusController.rebuildSpaceItems(registry: registry)
        showSetupRequirementsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        spaceSwitcherController.stop()
        windowSwitcherController.stop()
        activationController.stop()
    }

    @objc private func activeSpaceChanged() {
        guard !isSettingsOpen else { return }
        registry.refreshSpacesSoon()
    }

    private func showSettings() {
        pauseBackgroundUpdates()

        if settingsWindow == nil {
            registry.refreshSpaces()
            let coordinator = SettingsCoordinator(
                activationSettings: ActivationSettings.shared,
                onAppearanceChange: { [weak self] in
                    self?.applyAppearanceImmediately()
                }
            )
            settingsCoordinator = coordinator
            let host = NSHostingController(rootView: SettingsView(coordinator: coordinator))
            settingsHostingController = host
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 640, height: 720)
            window.center()
            window.title = "StayHere Settings"
            window.contentViewController = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            AppearanceManager.applyCurrentMode(to: [window])
            settingsWindow = window
        } else {
            settingsCoordinator?.load()
        }

        presentWindow(settingsWindow)
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

    private func flushSettingsAndUI() {
        settingsCoordinator?.commitAll()
        applyAppearanceImmediately()
        statusController.setTitle(registry.activeNameSummary())
        statusController.rebuildSpaceItems(registry: registry)
        settingsCoordinator = nil
    }

    private func applyAppearanceImmediately() {
        AppearanceManager.applyCurrentMode()
        statusController.applyCurrentAppearance()
    }

    private func presentWindow(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func demoteToAccessoryIfNoWindowsVisible() {
        let hasVisibleOwnedWindow = NSApp.windows.contains { $0.isVisible }
        if !hasVisibleOwnedWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func copySpaceState() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(registry.snapshotJSON(), forType: .string)
    }

    private func startEventDrivenControllers() {
        activationController.start()
        spaceSwitcherController.start()
        windowSwitcherController.start()
    }

    private func showSetupRequirementsIfNeeded() {
        let shortcutConfiguration = MissionControlShortcutConfigurator.ensureControlNumberShortcutsEnabled()
        if shortcutConfiguration.changed {
            Logger.shared.info("setup auto-enabled=mission-control-shortcuts")
        }

        let status = StayHereSetupStatus.current()
        guard !status.isSatisfied else {
            startEventDrivenControllers()
            return
        }

        Logger.shared.error("setup requirements missing=\(status.missingDescriptions.joined(separator: ", "))")
        presentSetupRequirementsWarning()
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
            • Input Monitoring lets StayHere listen for global keyboard and mouse events, including the switchers and Dock click interception.
            • Control+1 through Control+9 under Mission Control are the built-in shortcuts StayHere relies on for desktop switching.

            Use the checklist below. A green check means that item is ready; click any missing item to jump to the right System Settings pane, make the change, then return here and click Recheck. StayHere will start once every required item is checked. If something still does not work after you grant access, quit and reopen StayHere.

            StayHere goal is to deliver a focus-first experience to your workflow. 
            Therefore we encourage you to run it with additional settings:
            • Settings -> Desktop & Dock -> Automatically rearrange Spaces based on most recent use -> Off
            • Settings -> Desktop & Dock -> When switching to an application, switch to a Space with open windows for the application -> Off (prevents to teleporting to other spaces trough the Spotlight)
            • Settings -> Desktop & Dock -> Group windows by application -> On
            • Settings -> Desktop & Dock -> Displays have separate Spaces -> Off (it messes with spaces location across displays, when they disconnect)
            • Settings -> Desktop & Dock -> Show suggested and recent apps in Dock -> Off (you should only see what you need to make your work in your space done)
            """
            alert.addButton(withTitle: "Recheck")
            alert.addButton(withTitle: "Quit")

            let checklist = SetupChecklistAccessoryView(status: StayHereSetupStatus.current())
            alert.accessoryView = checklist
            AppearanceManager.applyCurrentMode(to: [alert.window])

            while true {
                checklist.refresh(with: StayHereSetupStatus.current())
                let response = alert.runModal()
                if response == .alertSecondButtonReturn {
                    NSApp.terminate(nil)
                    return
                }
                if StayHereSetupStatus.current().isSatisfied {
                    self.startEventDrivenControllers()
                    break
                }
            }

            self.demoteToAccessoryIfNoWindowsVisible()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else {
            demoteToAccessoryIfNoWindowsVisible()
            return
        }

        flushSettingsAndUI()

        settingsHostingController = nil
        settingsWindow = nil

        demoteToAccessoryIfNoWindowsVisible()
    }
}

let app = NSApplication.shared
// Keep a strong process-lifetime reference: NSApplication.delegate is not a retaining owner.
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
