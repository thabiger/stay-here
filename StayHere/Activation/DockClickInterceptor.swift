import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import Core

public final class DockClickInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let shouldIntercept: (String, Bool) -> Bool
    private let handler: (String, Bool) -> Bool
    private var pendingDockClick: PendingDockClick?

    private struct PendingDockClick {
        let bundleID: String
        let optionHeld: Bool
    }

    public init(
        shouldIntercept: @escaping (String, Bool) -> Bool,
        handler: @escaping (String, Bool) -> Bool
    ) {
        self.shouldIntercept = shouldIntercept
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard (type == .leftMouseDown || type == .leftMouseUp),
                  let refcon else { return Unmanaged.passRetained(event) }

            let interceptor = Unmanaged<DockClickInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handle(proxy: proxy, event: event)
        }

        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: ref
        ) else {
            Logger.shared.error("activation intercept tap-create-failed")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        Logger.shared.info("activation intercept started")
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        if !ActivationSettings.shared.dockClickInterceptionEnabled {
            pendingDockClick = nil
            return Unmanaged.passRetained(event)
        }

        let optionHeld = event.flags.contains(.maskAlternate)
        let point = event.location

        switch event.type {
        case .leftMouseDown:
            guard let bundleID = dockBundleID(at: point) else {
                return Unmanaged.passRetained(event)
            }

            guard shouldIntercept(bundleID, optionHeld) else {
                Logger.shared.info("activation dock-down passthrough=true option=\(optionHeld)")
                return Unmanaged.passRetained(event)
            }

            pendingDockClick = PendingDockClick(bundleID: bundleID, optionHeld: optionHeld)
            Logger.shared.info("activation dock-down option=\(optionHeld)")
            return nil

        case .leftMouseUp:
            let currentBundleID = dockBundleID(at: point)
            let pending = pendingDockClick
            pendingDockClick = nil

            guard let bundleID = pending?.bundleID ?? currentBundleID else {
                return Unmanaged.passRetained(event)
            }

            let resolvedOptionHeld = pending?.optionHeld ?? optionHeld
            Logger.shared.info("activation dock-up option=\(resolvedOptionHeld)")
            if handler(bundleID, resolvedOptionHeld) {
                return nil
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func dockBundleID(at point: CGPoint) -> String? {
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
