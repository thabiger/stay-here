import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import Core

public final class DockClickInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (String, Bool) -> Void

    public init(handler: @escaping (String, Bool) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard type == .leftMouseDown,
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

        let mode = ActivationSettings.shared.mode
        if mode == .disabled {
            return Unmanaged.passRetained(event)
        }

        let optionHeld = event.flags.contains(.maskAlternate)
        if mode == .optionOnly && !optionHeld {
            return Unmanaged.passRetained(event)
        }

        let point = event.location
        guard let bundleID = dockBundleID(at: point) else {
            return Unmanaged.passRetained(event)
        }

        handler(bundleID, optionHeld)
        return nil
    }

    private func dockBundleID(at point: CGPoint) -> String? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var hitRef: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hitRef)
        guard hitResult == .success, let hit = hitRef else { return nil }

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
}
