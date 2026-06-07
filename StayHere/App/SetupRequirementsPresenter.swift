import AppKit
import Foundation
import Core

@MainActor
final class SetupRequirementsPresenter {
    private let appearanceManager: AppearanceManager
    private let switchPresentationHelper: SpaceSwitchPresentationHelper

    init(
        appearanceManager: AppearanceManager,
        switchPresentationHelper: SpaceSwitchPresentationHelper
    ) {
        self.appearanceManager = appearanceManager
        self.switchPresentationHelper = switchPresentationHelper
    }

    func presentSetupRequirementsWarning() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Set up StayHere before you start"
            alert.informativeText = """
            StayHere runs from the menu bar and helps you name Spaces, switch between them, pick windows on the current Space, and keep Dock clicks on the desktop you are using.

            To do that, macOS needs to allow a few things:

            • Accessibility lets StayHere focus apps, read Dock state, and apply space-related behavior.
            • Control+<Number> under Mission Control are the built-in shortcuts StayHere relies on for desktop switching (this one is under Settings -> Keyboard -> Keyboard Shortcuts -> Mission Control).

            Use the checklist below. A green check means that item is ready; click any missing item to jump to the right System Settings pane, make the change, then return here and click Reload to relaunch StayHere. StayHere will start once every required item is checked.
            """
            alert.addButton(withTitle: "OK")

            let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            let supplementaryText = NSMutableAttributedString(
                string: "StayHere goal is to deliver a focus-first experience to your workflow. Therefore we encourage you to run it with additional settings:\n",
                attributes: [.font: boldFont]
            )
            supplementaryText.append(NSAttributedString(
                string: """
                • Settings -> Desktop & Dock -> Automatically rearrange Spaces based on most recent use -> Off
                • Settings -> Desktop & Dock -> When switching to an application, switch to a Space with open windows for the application -> Off (prevents teleporting to other spaces through Spotlight)
                • Settings -> Desktop & Dock -> Group windows by application -> On
                • Settings -> Desktop & Dock -> Displays have separate Spaces -> Off (it messes with spaces location across displays, when they disconnect)
                • Settings -> Desktop & Dock -> Show suggested and recent apps in Dock -> Off (you should only see what you need to make your work in your space done)

                Please click OK when you've made the changes and start the app again.
                """,
                attributes: [.font: bodyFont]
            ))

            let checklist = SetupChecklistAccessoryView(
                status: StayHereSetupStatus.current(),
                supplementaryText: supplementaryText
            )
            alert.accessoryView = checklist
            self.appearanceManager.applyCurrentMode(to: [alert.window])
            self.switchPresentationHelper.ensureAlertWidth(alert, minimumWidth: 720)

            checklist.refresh(with: StayHereSetupStatus.current())
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        }
    }

    func reloadApplication() {
        let bundleURL = Bundle.main.bundleURL
        Logger.shared.info("reload requested")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if error != nil {
                Logger.shared.error("failed to reload app after setup changes")
                Logger.shared.flush()
                Task { @MainActor in
                    self.showReloadFailureAlert()
                }
                return
            }
            Logger.shared.info("reload launch request succeeded")
            Logger.shared.flush()
            NSApp.terminate(nil)
        }
    }

    func showReloadFailureAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "StayHere couldn't reload"
            alert.informativeText = "Quit and reopen StayHere to apply the macOS permission changes."
            alert.addButton(withTitle: "OK")
            self.appearanceManager.applyCurrentMode(to: [alert.window])
            self.switchPresentationHelper.ensureAlertWidth(alert, minimumWidth: 420)
            _ = alert.runModal()
        }
    }
}
