import AppKit
import SwiftUI
import Core

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    private let settings: SettingsRepository
    private let appearanceManager: AppearanceManager
    private let onAppearanceChange: () -> Void
    var onWillOpen: () -> Void
    var onDidClose: () -> Void
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activateApp: () -> Void
    private let hasVisibleOwnedWindow: () -> Bool

    private(set) var settingsWindow: NSWindow?
    private(set) var settingsHostingController: NSHostingController<SettingsView>?
    private(set) var settingsCoordinator: SettingsCoordinator?

    init(
        settings: SettingsRepository,
        appearanceManager: AppearanceManager,
        onAppearanceChange: @escaping () -> Void,
        onWillOpen: @escaping () -> Void = {},
        onDidClose: @escaping () -> Void = {},
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        hasVisibleOwnedWindow: @escaping () -> Bool = { NSApp.windows.contains { $0.isVisible } }
    ) {
        self.settings = settings
        self.appearanceManager = appearanceManager
        self.onAppearanceChange = onAppearanceChange
        self.onWillOpen = onWillOpen
        self.onDidClose = onDidClose
        self.setActivationPolicy = setActivationPolicy
        self.activateApp = activateApp
        self.hasVisibleOwnedWindow = hasVisibleOwnedWindow
    }

    var isOpen: Bool { settingsWindow != nil }

    func showSettings(refreshRegistry: @escaping () -> Void) {
        onWillOpen()

        if settingsWindow == nil {
            refreshRegistry()
            let coordinator = SettingsCoordinator(
                settings: settings,
                onAppearanceChange: onAppearanceChange
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
            appearanceManager.applyCurrentMode(to: [window])
            settingsWindow = window
        } else {
            settingsCoordinator?.load()
        }

        presentWindow(settingsWindow)
    }

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

    private func flushSettingsAndUI() {
        settingsCoordinator?.commitAll()
        settingsCoordinator = nil
        onDidClose()
    }

    private func presentWindow(_ window: NSWindow?) {
        guard let window else { return }
        setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        activateApp()
    }

    private func demoteToAccessoryIfNoWindowsVisible() {
        if !hasVisibleOwnedWindow() {
            setActivationPolicy(.accessory)
        }
    }
}
