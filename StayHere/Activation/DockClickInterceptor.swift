import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import Core

public final class DockClickInterceptor: CGEventTapClient {
    private let isDockClickInterceptionEnabled: () -> Bool
    private let shouldIntercept: (String, Bool) -> Bool
    private let handler: (String, Bool) -> Bool
    private let logger: any Logging
    private var pendingDockClick: PendingDockClick?

    struct PendingDockClick {
        let bundleID: String
        let optionHeld: Bool
    }

    var testPendingDockClick: PendingDockClick? {
        get { pendingDockClick }
        set { pendingDockClick = newValue }
    }

    var testDockBundleIDResolver: ((CGPoint) -> String?)?

    public var hasActiveSession: Bool { false }
    public var handlesKeyboardEvents: Bool { false }
    public var handlesMouseEvents: Bool { isDockClickInterceptionEnabled() }

    public init(
        settings: ActivationSettings,
        shouldIntercept: @escaping (String, Bool) -> Bool,
        handler: @escaping (String, Bool) -> Bool,
        logger: any Logging
    ) {
        self.isDockClickInterceptionEnabled = { settings.activationDockClickInterceptionEnabled }
        self.shouldIntercept = shouldIntercept
        self.handler = handler
        self.logger = logger
    }

    public func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let dockClickEnabled = isDockClickInterceptionEnabled()
        if !dockClickEnabled {
            pendingDockClick = nil
            return Unmanaged.passUnretained(event)
        }

        let optionHeld = event.flags.contains(.maskAlternate)
        let point = event.location

        switch event.type {
        case .leftMouseDown:
            guard let bundleID = dockBundleID(at: point) else {
                return Unmanaged.passUnretained(event)
            }

            guard shouldIntercept(bundleID, optionHeld) else {
                logger.info("activation dock-down passthrough=true option=\(optionHeld)")
                return Unmanaged.passUnretained(event)
            }

            pendingDockClick = PendingDockClick(bundleID: bundleID, optionHeld: optionHeld)
            logger.info("activation dock-down option=\(optionHeld)")
            return nil

        case .leftMouseUp:
            let currentBundleID = dockBundleID(at: point)
            let pending = pendingDockClick
            pendingDockClick = nil

            if let pendingBundleID = pending?.bundleID,
               let currentBundleID,
               currentBundleID != pendingBundleID {
                return Unmanaged.passUnretained(event)
            }

            guard let bundleID = pending?.bundleID ?? currentBundleID else {
                return Unmanaged.passUnretained(event)
            }

            let resolvedOptionHeld = pending?.optionHeld ?? optionHeld
            logger.info("activation dock-up option=\(resolvedOptionHeld)")
            if handler(bundleID, resolvedOptionHeld) {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func dockBundleID(at point: CGPoint) -> String? {
        if let testDockBundleIDResolver {
            return testDockBundleIDResolver(point)
        }

        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var hitRef: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hitRef)
        guard hitResult == .success, let hit = hitRef else { return nil }

        guard isDockItem(hit) else { return nil }

        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(hit, kAXURLAttribute as CFString, &urlValue) == .success,
           let url = urlValue as? URL,
           let bundleID = Bundle(url: url)?.bundleIdentifier {
            return bundleID
        }

        var titleValue: CFTypeRef?
        let running = NSWorkspace.shared.runningApplications
        if AXUIElementCopyAttributeValue(hit, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String,
           let app = running.first(where: { $0.localizedName == title }) {
            return app.bundleIdentifier
        }

        return nil
    }

    private func isDockItem(_ element: AXUIElement) -> Bool {
        let acceptedSubroles: Set<String> = [
            "AXApplicationDockItem",
            "AXMinimizedWindowDockItem"
        ]

        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
              let subrole = subroleValue as? String else {
            return false
        }

        return acceptedSubroles.contains(subrole)
    }
}
