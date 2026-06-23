import AppKit
import Core

@MainActor
final class SpaceSwitchPresentationHelper {
    struct WarningPayload: Equatable {
        let title: String
        let message: String
    }

    private let appearanceManager: AppearanceManager
    private let activateApp: () -> Void
    private let openURL: (URL) -> Bool
    private let openSystemSettingsApp: () -> Void

    init(
        appearanceManager: AppearanceManager,
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        openSystemSettingsApp: @escaping () -> Void = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    ) {
        self.appearanceManager = appearanceManager
        self.activateApp = activateApp
        self.openURL = openURL
        self.openSystemSettingsApp = openSystemSettingsApp
    }

    func presentWarning(for result: SpaceSwitchResult) {
        guard let payload = warningPayload(for: result) else { return }
        presentMissionControlShortcutWarning(title: payload.title, message: payload.message)
    }

    func warningPayload(for result: SpaceSwitchResult) -> WarningPayload? {
        switch result {
        case .switched, .alreadyActive, .unknownSpace:
            return nil
        case .unsupportedSpaceKind:
            return WarningPayload(
                title: "This space can't be switched",
                message: """
                StayHere can switch regular desktops through Mission Control shortcuts, but macOS does not expose an equivalent shortcut for fullscreen app spaces.

                The space will stay visible in StayHere, but it is currently informational only unless you are already on it.
                """
            )
        case .unsupportedDesktop(let index):
            return WarningPayload(
                title: "Desktop \(index) can't be switched",
                message: "StayHere can switch only desktops 1 through 9 using Mission Control shortcuts."
            )
        case .eventPostFailed(let index):
            return WarningPayload(
                title: "Desktop \(index) couldn't be switched",
                message: """
                StayHere couldn't send the Mission Control shortcut for Desktop \(index). Check System Settings > Keyboard > Keyboard Shortcuts > Mission Control and make sure "Switch to Desktop \(index)" is enabled.

                For the best experience, consider enabling shortcuts for all desktops to prevent this issue in the future.
                """
            )
        case .switchUnmatched(let index, _, _):
            return WarningPayload(
                title: "Desktop \(index) didn't switch",
                message: """
                StayHere sent the Mission Control shortcut for Desktop \(index), but macOS stayed on the current desktop.

                This usually means "Switch to Desktop \(index)" is not active yet in System Settings, or macOS has not picked up a recently added desktop shortcut while StayHere was already running. Open System Settings > Keyboard > Keyboard Shortcuts > Mission Control and confirm "Switch to Desktop \(index)" is enabled.

                If you just added or enabled that shortcut, quit and reopen StayHere once so it re-syncs with the updated Mission Control configuration.
                """
            )
        }
    }

    func openKeyboardShortcutsSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts"),
           openURL(deepLink) {
            return
        }

        openSystemSettingsApp()
    }

    func ensureAlertWidth(_ alert: NSAlert, minimumWidth: CGFloat) {
        let window = alert.window
        window.layoutIfNeeded()
        var frame = window.frame
        guard frame.width < minimumWidth else { return }
        frame.size.width = minimumWidth
        window.setFrame(frame, display: false)
    }

    private func presentMissionControlShortcutWarning(title: String, message: String) {
        DispatchQueue.main.async {
            self.activateApp()

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            self.appearanceManager.applyCurrentMode(to: [alert.window])
            self.ensureAlertWidth(alert, minimumWidth: 560)

            if alert.runModal() == .alertFirstButtonReturn {
                self.openKeyboardShortcutsSettings()
            }
        }
    }
}
