import AppKit
import ApplicationServices
import CoreGraphics

struct MacOSPermissionStatus: Equatable {
    let accessibilityGranted: Bool

    var isSatisfied: Bool {
        accessibilityGranted
    }

    var missingPermissionNames: [String] {
        var names: [String] = []
        if !accessibilityGranted {
            names.append("Accessibility")
        }
        return names
    }
}

enum MacOSPermissionKind: CaseIterable {
    case accessibility

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        }
    }

    var settingsPane: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        }
    }

    func isGranted(in status: MacOSPermissionStatus) -> Bool {
        switch self {
        case .accessibility: return status.accessibilityGranted
        }
    }
}

enum MacOSPermissionCheck {
    static func currentStatus() -> MacOSPermissionStatus {
        MacOSPermissionStatus(
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    static func openSettings(for permission: MacOSPermissionKind) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)")!
        NSWorkspace.shared.open(url)
    }
}
