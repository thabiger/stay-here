import AppKit
import SwiftUI

final class AboutWindowManager: NSObject, NSWindowDelegate {
    private let appearanceManager: AppearanceManager
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let activateApp: () -> Void
    private let hasVisibleOwnedWindow: () -> Bool

    private(set) var aboutWindow: NSWindow?
    private(set) var aboutHostingController: NSHostingController<AboutView>?

    init(
        appearanceManager: AppearanceManager,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        hasVisibleOwnedWindow: @escaping () -> Bool = { NSApp.windows.contains { $0.isVisible } }
    ) {
        self.appearanceManager = appearanceManager
        self.setActivationPolicy = setActivationPolicy
        self.activateApp = activateApp
        self.hasVisibleOwnedWindow = hasVisibleOwnedWindow
        super.init()
    }

    var isOpen: Bool { aboutWindow != nil }

    func showAbout() {
        if aboutWindow == nil {
            let host = NSHostingController(rootView: AboutView())
            aboutHostingController = host

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 350),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "About StayHere"
            window.contentViewController = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            appearanceManager.applyCurrentMode(to: [window])
            aboutWindow = window
        }

        presentWindow(aboutWindow)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === aboutWindow else {
            demoteToAccessoryIfNoWindowsVisible()
            return
        }

        aboutHostingController = nil
        aboutWindow = nil
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
}
