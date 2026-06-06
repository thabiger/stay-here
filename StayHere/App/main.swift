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
        self?.performSpaceSwitch(spaceID)
    }, onShowSingleWindowHint: { [weak self] message in
        self?.hudController.show(message: message)
    })
    private lazy var spaceSwitcherController = SpaceSwitcherController(
        registry: registry,
        switchToSpace: { [weak self] spaceID in
            self?.performSpaceSwitch(spaceID)
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

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isSettingsOpen else { return }
            self.registry.refreshSpacesSoon()
        }

        registry.refreshSpacesAsync()
        statusController.rebuildSpaceItems(registry: registry)
        showSetupRequirementsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("application will terminate")
        Logger.shared.flush()
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
        let status = StayHereSetupStatus.current()
        guard !status.isSatisfied else {
            startEventDrivenControllers()
            return
        }

        Logger.shared.error("setup requirements missing=\(status.missingDescriptions.joined(separator: ", "))")
        presentSetupRequirementsWarning()
    }

    private func performSpaceSwitch(_ spaceID: Int) {
        let result = registry.switchToSpace(spaceID)
        switch result {
        case .switched, .alreadyActive:
            return
        case .unknownSpace:
            return
        case .unsupportedSpaceKind:
            presentMissionControlShortcutWarning(
                title: "This space can't be switched",
                message: """
                StayHere can switch regular desktops through Mission Control shortcuts, but macOS does not expose an equivalent shortcut for fullscreen app spaces.

                The space will stay visible in StayHere, but it is currently informational only unless you are already on it.
                """
            )
        case .unsupportedDesktop(let index):
            presentMissionControlShortcutWarning(
                title: "Desktop \(index) can't be switched",
                message: "StayHere can switch only desktops 1 through 9 using Mission Control shortcuts."
            )
        case .eventPostFailed(let index):
            presentMissionControlShortcutWarning(
                title: "Desktop \(index) couldn't be switched",
                message: """
                StayHere couldn't send the Mission Control shortcut for Desktop \(index). Check System Settings > Keyboard > Keyboard Shortcuts > Mission Control and make sure \"Switch to Desktop \(index)\" is enabled.

                For the best experience, consider enabling shortcuts for all desktops to prevent this issue in the future.
                """
            )
        case .switchUnmatched(let index, _, _):
            presentMissionControlShortcutWarning(
                title: "Desktop \(index) didn't switch",
                message: """
                StayHere sent the Mission Control shortcut for Desktop \(index), but macOS stayed on the current desktop.

                This usually means "Switch to Desktop \(index)" is not active yet in System Settings, or macOS has not picked up a recently added desktop shortcut while StayHere was already running. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control and confirm "Switch to Desktop \(index)" is enabled.

                If you just added or enabled that shortcut, quit and reopen StayHere once so it re-syncs with the updated Mission Control configuration.
                """
            )
        }
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
            AppearanceManager.applyCurrentMode(to: [alert.window])
            self.ensureAlertWidth(alert, minimumWidth: 720)

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
        Logger.shared.info("reload requested bundleURL=\(bundleURL.path)")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                Logger.shared.error("failed to reload app after setup changes: \(error.localizedDescription)")
                Logger.shared.flush()
                self.showReloadFailureAlert()
                return
            }
            Logger.shared.info("reload launch request succeeded, terminating current instance")
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
            AppearanceManager.applyCurrentMode(to: [alert.window])
            self.ensureAlertWidth(alert, minimumWidth: 420)
            _ = alert.runModal()
        }
    }

    private func presentMissionControlShortcutWarning(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            AppearanceManager.applyCurrentMode(to: [alert.window])
            self.ensureAlertWidth(alert, minimumWidth: 560)

            if alert.runModal() == .alertFirstButtonReturn {
                self.openKeyboardShortcutsSettings()
            }
        }
    }

    private func openKeyboardShortcutsSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(settingsURL)
    }

    private func ensureAlertWidth(_ alert: NSAlert, minimumWidth: CGFloat) {
        let window = alert.window
        window.layoutIfNeeded()
        var frame = window.frame
        guard frame.width < minimumWidth else { return }
        frame.size.width = minimumWidth
        window.setFrame(frame, display: false)
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
