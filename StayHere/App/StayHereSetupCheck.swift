import AppKit
import Core

struct StayHereSetupStatus: Equatable {
    let permissions: MacOSPermissionStatus
    let missionControl: MissionControlShortcutCheck.Result

    var isSatisfied: Bool {
        permissions.isSatisfied && missionControl.isSatisfied
    }

    var missingDescriptions: [String] {
        permissions.missingPermissionNames + missionControl.missingDescriptions
    }

    static func current() -> StayHereSetupStatus {
        StayHereSetupStatus(
            permissions: MacOSPermissionCheck.currentStatus(),
            missionControl: MissionControlShortcutCheck.check()
        )
    }
}

struct SetupChecklistItem: Equatable {
    enum FixTarget: Equatable {
        case accessibility
        case missionControlShortcuts
    }

    let displayName: String
    let isSatisfied: Bool
    let fixTarget: FixTarget?
}

enum StayHereSetupCheck {
    static func checklistItems(for status: StayHereSetupStatus) -> [SetupChecklistItem] {
        var items: [SetupChecklistItem] = []

        for permission in MacOSPermissionKind.allCases {
            items.append(
                SetupChecklistItem(
                    displayName: permission.displayName,
                    isSatisfied: permission.isGranted(in: status.permissions),
                    fixTarget: permission.fixTarget
                )
            )
        }

        for itemStatus in status.missionControl.itemStatuses {
            items.append(
                SetupChecklistItem(
                    displayName: itemStatus.displayName,
                    isSatisfied: itemStatus.isSatisfied,
                    fixTarget: itemStatus.isSatisfied ? nil : .missionControlShortcuts
                )
            )
        }

        return items
    }

    static func openSettings(for target: SetupChecklistItem.FixTarget) {
        switch target {
        case .accessibility:
            MacOSPermissionCheck.openSettings(for: .accessibility)
        case .missionControlShortcuts:
            let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts")!
            NSWorkspace.shared.open(url)
        }
    }
}

private extension MacOSPermissionKind {
    var fixTarget: SetupChecklistItem.FixTarget {
        switch self {
        case .accessibility: return .accessibility
        }
    }
}
