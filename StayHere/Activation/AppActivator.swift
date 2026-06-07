import Foundation
import AppKit
import ApplicationServices

public protocol RunningApplicationControlling {
    var processIdentifier: pid_t { get }
    var isActive: Bool { get }
    var localizedName: String? { get }

    @discardableResult
    func unhide() -> Bool
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplicationControlling {}

public final class AppActivator {
    private let runningApplications: (String) -> [any RunningApplicationControlling]
    private let appURL: (String) -> URL?
    private let openApplication: (URL, NSWorkspace.OpenConfiguration, @escaping (Error?) -> Void) -> Void

    public init(
        runningApplications: @escaping (String) -> [any RunningApplicationControlling] = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        },
        appURL: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration, @escaping (Error?) -> Void) -> Void = {
            url, configuration, completion in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                completion(error)
            }
        }
    ) {
        self.runningApplications = runningApplications
        self.appURL = appURL
        self.openApplication = openApplication
    }

    public func launch(bundleID: String) {
        guard let appURL = appURL(bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        openApplication(appURL, config) { _ in }
    }

    public func focus(bundleID: String) {
        guard let app = runningApplications(bundleID).first else { return }
        _ = app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        if activated, app.isActive {
            return
        }

        raiseApplicationWindows(app)
        if app.isActive {
            return
        }

        guard let appURL = appURL(bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        openApplication(appURL, config) { _ in }
    }

    public func displayName(forBundleID bundleID: String) -> String? {
        runningApplications(bundleID).first?.localizedName
    }

    public func isAppActive(bundleID: String) -> Bool {
        runningApplications(bundleID).first?.isActive == true
    }

    private func raiseApplicationWindows(_ app: any RunningApplicationControlling) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return
        }

        let target = windows.first(where: isStandardWindow) ?? windows.first!
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
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
