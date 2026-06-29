import AppKit
import SwiftUI
import Core

@MainActor
protocol UpdateWindowManaging: AnyObject {
    func showUpdate(
        _ updateInfo: UpdateInfo,
        onDownload: @escaping () -> Void,
        onViewReleaseNotes: @escaping () -> Void,
        onLater: @escaping () -> Void
    )
    func close()
}

@MainActor
protocol UpdateAlertPresenting: AnyObject {
    func presentUpToDateAlert()
    func presentErrorAlert(message: String)
}

@MainActor
final class UpdateWindowManager: NSObject, NSWindowDelegate, UpdateWindowManaging, UpdateAlertPresenting {
    private let appearanceManager: AppearanceManager
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activateApp: () -> Void
    private let hasVisibleOwnedWindow: () -> Bool

    private(set) var updateWindow: NSWindow?
    private(set) var updateHostingController: NSHostingController<UpdateView>?

    init(
        appearanceManager: AppearanceManager,
        setActivationPolicy: ((NSApplication.ActivationPolicy) -> Void)? = nil,
        activateApp: (() -> Void)? = nil,
        hasVisibleOwnedWindow: (() -> Bool)? = nil
    ) {
        self.appearanceManager = appearanceManager
        self.setActivationPolicy = setActivationPolicy ?? { NSApp.setActivationPolicy($0) }
        self.activateApp = activateApp ?? { NSApp.activate(ignoringOtherApps: true) }
        self.hasVisibleOwnedWindow = hasVisibleOwnedWindow ?? { NSApp.windows.contains { $0.isVisible } }
        super.init()
    }

    func showUpdate(
        _ updateInfo: UpdateInfo,
        onDownload: @escaping () -> Void,
        onViewReleaseNotes: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        let rootView = UpdateView(
            updateInfo: updateInfo,
            onDownload: onDownload,
            onViewReleaseNotes: onViewReleaseNotes,
            onLater: onLater
        )

        if let hostingController = updateHostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            updateHostingController = hostingController

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "StayHere Update"
            window.center()
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.delegate = self
            appearanceManager.applyCurrentMode(to: [window])
            updateWindow = window
        }

        presentWindow(updateWindow)
    }

    func close() {
        updateWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === updateWindow else {
            demoteToAccessoryIfNoWindowsVisible()
            return
        }

        updateHostingController = nil
        updateWindow = nil
        demoteToAccessoryIfNoWindowsVisible()
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

    // MARK: - UpdateAlertPresenting

    func presentUpToDateAlert() {
        setActivationPolicy(.regular)
        activateApp()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You're up to date"
        alert.informativeText = "StayHere is already running the latest available version."
        alert.addButton(withTitle: "OK")
        appearanceManager.applyCurrentMode(to: [alert.window])
        _ = alert.runModal()
    }

    func presentErrorAlert(message: String) {
        setActivationPolicy(.regular)
        activateApp()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        appearanceManager.applyCurrentMode(to: [alert.window])
        _ = alert.runModal()
    }
}
