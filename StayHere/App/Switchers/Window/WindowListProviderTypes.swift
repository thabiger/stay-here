import AppKit
import ApplicationServices
import CoreGraphics

enum WindowListProviderTypes {
    typealias WindowInfoProvider = () -> [[String: Any]]?
    typealias RunningApplicationProvider = (pid_t) -> (any WindowListApplication)?
    typealias AccessibilityWindowTitlesProvider = (pid_t) -> [Int: String]
    typealias FocusedWindowIDProvider = () -> Int?
    typealias IconProvider = ((any WindowListApplication)?) -> NSImage

    static nonisolated func liveWindowInfoProvider() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    }

    static nonisolated func liveRunningApplicationProvider(pid: pid_t) -> (any WindowListApplication)? {
        NSRunningApplication(processIdentifier: pid)
    }

    static nonisolated func liveAccessibilityWindowTitlesProvider(pid: pid_t) -> [Int: String] {
        WindowTitleResolver.live(pid: pid)
    }

    /// Must only be called from the main actor. AXUIElement is not thread-safe.
    static nonisolated func liveFocusedWindowIDProvider() -> Int? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
              let window = windowRef else {
            return nil
        }

        var numberRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            "AXWindowNumber" as CFString,
            &numberRef
        ) == .success,
              let number = numberRef as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    static nonisolated func liveIconProvider(application: (any WindowListApplication)?) -> NSImage {
        WindowIconProvider().icon(for: application)
    }
}
