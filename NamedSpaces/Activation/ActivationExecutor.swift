import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Core

public final class ActivationExecutor {
    private let showSingleWindowHint: (String) -> Void
    private let switchToSpace: (Int) -> Void
    private let currentSpaceID: () -> Int?

    public init(
        showSingleWindowHint: @escaping (String) -> Void = { _ in },
        switchToSpace: @escaping (Int) -> Void = { _ in },
        currentSpaceID: @escaping () -> Int? = { nil }
    ) {
        self.showSingleWindowHint = showSingleWindowHint
        self.switchToSpace = switchToSpace
        self.currentSpaceID = currentSpaceID
    }

    public func execute(decision: ActivationDecision, context: ActivationContext) -> Bool {
        switch decision {
        case .launch:
            launch(bundleID: context.bundleID)
            return true
        case .focusCurrentSpace:
            focus(bundleID: context.bundleID)
            return true
        case .createNewWindow:
            focus(bundleID: context.bundleID)
            sendNewWindowShortcut(toBundleID: context.bundleID)
            return true
        case .singleWindowHint:
            showSingleWindowHint(singleWindowHintMessage(bundleID: context.bundleID))
            return true
        case .switchToSingleWindowSpace:
            return switchToAppSpace(context: context)
        case .consumeOnly:
            return true
        case .passthrough:
            return false
        }
    }

    public func switchToAppSpace(context: ActivationContext) -> Bool {
        guard let spaceID = context.singleWindowSpaceID ?? preferredSpaceID(for: context.appWindowSummary) else {
            return false
        }
        switchToSpace(spaceID)
        focusAfterSpaceSwitch(bundleID: context.bundleID, spaceID: spaceID)
        return true
    }

    private func preferredSpaceID(for summary: AppWindowSummary?) -> Int? {
        summary?.allWindows.compactMap(\.spaceIDs.first).first
    }

    private func launch(bundleID: String) {
        guard let appURL = appURL(bundleID: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
    }

    private func appURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func focus(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        if activated, app.isActive {
            return
        }

        raiseApplicationWindows(app)
        if app.isActive {
            return
        }

        // Fallback path when activation from an event-tap context is ignored by AppKit.
        guard let appURL = appURL(bundleID: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                Logger.shared.error("activation focus-fallback-failed bundle=\(bundleID) error=\(error.localizedDescription)")
            }
        }
    }

    private func sendNewWindowShortcut(toBundleID bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: false)
        up?.flags = .maskCommand
        down?.postToPid(app.processIdentifier)
        up?.postToPid(app.processIdentifier)
    }

    private func singleWindowHintMessage(bundleID: String) -> String {
        let appName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
        return "\(appName) was clicked. It is configured as a single-window app. Use Option+Click to switch to the space where it is running."
    }

    private func focusAfterSpaceSwitch(bundleID: String, spaceID: Int) {
        waitForActiveSpace(spaceID, timeout: 1.0) { [weak self] in
            self?.focus(bundleID: bundleID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self,
                      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                      !app.isActive else { return }
                self.focus(bundleID: bundleID)
            }
        }
    }

    private func waitForActiveSpace(_ spaceID: Int, timeout: TimeInterval, then: @escaping () -> Void) {
        let started = Date()

        func poll() {
            if currentSpaceID() == nil || currentSpaceID() == spaceID || Date().timeIntervalSince(started) >= timeout {
                then()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }

    private func raiseApplicationWindows(_ app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return
        }

        let target = windows.first(where: isStandardWindow) ?? windows.first!
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue!)
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else {
            return false
        }
        return subrole == kAXStandardWindowSubrole
    }
}
