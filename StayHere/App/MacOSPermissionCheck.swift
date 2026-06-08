import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ScreenRecordingPermissionCheck {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

struct MacOSPermissionStatus: Equatable {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool

    /// Whether the running macOS version still requires Input Monitoring
    /// permission for global event taps. Apple dropped the requirement
    /// starting with macOS 26 (Tahoe) — Accessibility alone is sufficient
    /// from that release onward. Centralized here so the data model and
    /// UI checklist stay in lockstep.
    static var inputMonitoringRequired: Bool {
        if let override = _inputMonitoringRequiredOverride { return override }
        if #available(macOS 26, *) { return false }
        return true
    }

    private static var _inputMonitoringRequiredOverride: Bool?

    /// Test seam — call with `true`/`false` to simulate the relevant
    /// macOS generation, or `nil` to restore runtime detection.
    /// Documented for test use; do not call from production code.
    static func _setInputMonitoringRequiredOverrideForTests(_ value: Bool?) {
        _inputMonitoringRequiredOverride = value
    }

    var isSatisfied: Bool {
        if !accessibilityGranted { return false }
        if Self.inputMonitoringRequired && !inputMonitoringGranted { return false }
        return true
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if !accessibilityGranted {
            names.append("Accessibility")
        }
        if Self.inputMonitoringRequired && !inputMonitoringGranted {
            names.append("Input Monitoring")
        }
        return names
    }
}

enum MacOSPermissionKind: CaseIterable {
    case accessibility
    case inputMonitoring

    /// Whether this permission must be granted on the current macOS
    /// version. `.inputMonitoring` is `false` on macOS 26+ (Tahoe).
    var isRequiredOnCurrentOS: Bool {
        switch self {
        case .accessibility: return true
        case .inputMonitoring: return MacOSPermissionStatus.inputMonitoringRequired
        }
    }

    /// Permissions that the user must actually grant on the current
    /// macOS version. Used by the setup checklist so Input Monitoring
    /// is hidden on macOS 26+.
    static var availableCases: [MacOSPermissionKind] {
        allCases.filter(\.isRequiredOnCurrentOS)
    }

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var settingsPane: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .inputMonitoring: return "Privacy_ListenEvent"
        }
    }

    func isGranted(in status: MacOSPermissionStatus) -> Bool {
        switch self {
        case .accessibility: return status.accessibilityGranted
        case .inputMonitoring: return status.inputMonitoringGranted
        }
    }
}

enum MacOSPermissionCheck {
    /// Resolves `CGPreflightListenForAccess` at runtime via dlsym.
    /// The symbol is part of the private CoreGraphics ABI (declared in
    /// the binary but absent from the public SDK headers and Swift
    /// overlay). Falls back to `false` on resolution failure so the
    /// setup checklist still surfaces the issue.
    private static let preflightListenForAccessImpl: () -> Bool = {
        typealias Impl = @convention(c) () -> Bool
        guard let handle = dlopen(nil, RTLD_NOW) else { return { false } }
        guard let sym = dlsym(handle, "CGPreflightListenForAccess") else { return { false } }
        let fn = unsafeBitCast(sym, to: Impl.self)
        return { fn() }
    }()

    static func currentStatus() -> MacOSPermissionStatus {
        currentStatus(
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            isInputMonitoringGranted: preflightListenForAccessImpl
        )
    }

    /// Test seam — callers can inject trusted C API closures to avoid
    /// touching real permission state during unit tests.
    static func currentStatus(
        isAccessibilityTrusted: () -> Bool,
        isInputMonitoringGranted: () -> Bool
    ) -> MacOSPermissionStatus {
        MacOSPermissionStatus(
            accessibilityGranted: isAccessibilityTrusted(),
            inputMonitoringGranted: isInputMonitoringGranted()
        )
    }

    static func openSettings(for permission: MacOSPermissionKind) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)")!
        NSWorkspace.shared.open(url)
    }
}
