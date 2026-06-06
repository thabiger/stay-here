import AppKit
import ApplicationServices
import CoreGraphics

struct MacOSPermissionStatus: Equatable {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool

    var isSatisfied: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if !accessibilityGranted {
            names.append("Accessibility")
        }
        if !inputMonitoringGranted {
            names.append("Input Monitoring")
        }
        return names
    }
}

enum MacOSPermissionKind: CaseIterable {
    case accessibility
    case inputMonitoring

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
    static func currentStatus() -> MacOSPermissionStatus {
        MacOSPermissionStatus(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    static func openSettings(for permission: MacOSPermissionKind) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)")!
        NSWorkspace.shared.open(url)
    }
}
