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
    private var settingsWindow: NSWindow?
    private var settingsHostingController: NSHostingController<SettingsView>?
    private var settingsCoordinator: SettingsCoordinator?
    private var cancellables: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var menuRebuildWorkItem: DispatchWorkItem?

    var isSettingsOpen: Bool { settingsWindow != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        activationController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                registry: registry,
                activationSettings: ActivationSettings.shared
            )
            settingsCoordinator = coordinator
            let host = NSHostingController(rootView: SettingsView(coordinator: coordinator))
            settingsHostingController = host
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Named Spaces Settings"
            window.contentViewController = host
            window.isReleasedWhenClosed = false
            window.delegate = self
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
        guard !isSettingsOpen else { return }
        menuRebuildWorkItem?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.isSettingsOpen else { return }
            self.statusController.rebuildSpaceItems(registry: self.registry)
        }
        menuRebuildWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    private func flushSettingsAndUI() {
        settingsCoordinator?.commitAll()
        statusController.setTitle(registry.activeNameSummary())
        statusController.rebuildSpaceItems(registry: registry)
        settingsCoordinator = nil
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
