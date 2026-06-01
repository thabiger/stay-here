import Foundation
import AppKit
import CoreGraphics
import Core

public final class ActivationExecutor {
    public init() {}

    public func execute(decision: ActivationDecision, context: ActivationContext) {
        switch decision {
        case .launch:
            launch(bundleID: context.bundleID)
        case .focusCurrentSpace:
            focus(bundleID: context.bundleID)
        case .createNewWindow:
            focus(bundleID: context.bundleID)
            sendNewWindowShortcut(toBundleID: context.bundleID)
        case .moveSingleWindow:
            moveSingleWindowAndFocus(context)
        case .passthrough:
            break
        }
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
        if activated {
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

    private func moveSingleWindowAndFocus(_ context: ActivationContext) {
        guard let targetSpace = context.targetSpaceID,
              let summary = context.appWindowSummary,
              let windowID = summary.allWindows.first?.windowID else {
            focus(bundleID: context.bundleID)
            return
        }

        let moved = CGSBridge.moveWindowToSpace(windowID: windowID, spaceID: targetSpace)
        Logger.shared.info("activation move-window bundle=\(context.bundleID) window=\(windowID) space=\(targetSpace) success=\(moved)")
        focus(bundleID: context.bundleID)
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
}
