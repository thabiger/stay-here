import AppKit
import Activation
import ApplicationServices
import Foundation

struct WindowFocusTarget {
    let title: String?
    let unminimize: () -> Void
    let raise: () -> Void
    let makeMain: () -> Void
}

final class WindowFocusService {
    typealias RunningApplicationProvider = (pid_t) -> (any RunningApplicationControlling)?
    typealias AccessibilityWindowsProvider = (pid_t) -> [WindowFocusTarget]
    typealias RetryScheduler = (@escaping () -> Void) -> Void
    typealias ApplicationActivator = () -> Void

    private let runningApplicationProvider: RunningApplicationProvider
    private let accessibilityWindowsProvider: AccessibilityWindowsProvider
    private let retryScheduler: RetryScheduler
    private let applicationActivator: ApplicationActivator

    init(
        runningApplicationProvider: @escaping RunningApplicationProvider = WindowFocusService.liveRunningApplicationProvider,
        accessibilityWindowsProvider: @escaping AccessibilityWindowsProvider = WindowFocusService.liveAccessibilityWindowsProvider,
        retryScheduler: @escaping RetryScheduler = WindowFocusService.liveRetryScheduler,
        applicationActivator: @escaping ApplicationActivator = WindowFocusService.liveApplicationActivator
    ) {
        self.runningApplicationProvider = runningApplicationProvider
        self.accessibilityWindowsProvider = accessibilityWindowsProvider
        self.retryScheduler = retryScheduler
        self.applicationActivator = applicationActivator
    }

    func focusWindow(entry: WindowEntry) {
        applicationActivator()
        guard let app = runningApplicationProvider(entry.pid) else {
            return
        }

        let wasActive = app.isActive
        _ = app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        if !activated || !app.isActive {
            raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
            retryScheduler {
                guard let app = self.runningApplicationProvider(entry.pid), !app.isActive else { return }
                _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                self.raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
            }
            return
        }

        raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
        if !wasActive {
            retryScheduler {
                self.raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
            }
        }
    }

    private func raiseWindow(pid: pid_t, title: String) {
        let windows = accessibilityWindowsProvider(pid)
        guard !windows.isEmpty else { return }

        let target = windows.first(where: { $0.title == title }) ?? windows.first!
        target.unminimize()
        target.raise()
        target.makeMain()
    }

    private static func liveRunningApplicationProvider(pid: pid_t) -> (any RunningApplicationControlling)? {
        NSRunningApplication(processIdentifier: pid)
    }

    private static func liveAccessibilityWindowsProvider(pid: pid_t) -> [WindowFocusTarget] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return []
        }

        return windows.map { window in
            WindowFocusTarget(
                title: liveTitle(for: window),
                unminimize: {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                },
                raise: {
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                },
                makeMain: {
                    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                }
            )
        }
    }

    private static func liveTitle(for window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return nil
        }
        return title
    }

    private static func liveRetryScheduler(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private static func liveApplicationActivator() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
