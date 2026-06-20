import AppKit
import Core

@MainActor
final class SwitcherCoordinator {
    private let spaceSwitcherController: SpaceSwitcherController
    private let windowSwitcherController: WindowSwitcherController
    private let allSpacesWindowSwitcherController: WindowSwitcherController
    private let settings: SettingsRepository

    init(
        spaceSwitcherController: SpaceSwitcherController,
        windowSwitcherController: WindowSwitcherController,
        allSpacesWindowSwitcherController: WindowSwitcherController,
        settings: SettingsRepository
    ) {
        self.spaceSwitcherController = spaceSwitcherController
        self.windowSwitcherController = windowSwitcherController
        self.allSpacesWindowSwitcherController = allSpacesWindowSwitcherController
        self.settings = settings
    }

    var hasActiveSession: Bool {
        windowSwitcherController.hasActiveSession
            || allSpacesWindowSwitcherController.hasActiveSession
            || spaceSwitcherController.hasActiveSession
    }

    func start() {
        if settings.spaceSwitcherEnabled {
            spaceSwitcherController.start()
        }
        if settings.windowSwitcherEnabled {
            windowSwitcherController.start()
        }
        if settings.allSpacesWindowSwitcherEnabled {
            allSpacesWindowSwitcherController.start()
        }
    }

    func stop() {
        spaceSwitcherController.stop()
        windowSwitcherController.stop()
        allSpacesWindowSwitcherController.stop()
    }

    func syncControllers() {
        if settings.spaceSwitcherEnabled {
            spaceSwitcherController.start()
        } else {
            spaceSwitcherController.stop()
        }

        if settings.windowSwitcherEnabled {
            windowSwitcherController.start()
        } else {
            windowSwitcherController.stop()
        }

        if settings.allSpacesWindowSwitcherEnabled {
            allSpacesWindowSwitcherController.start()
        } else {
            allSpacesWindowSwitcherController.stop()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard let command = SwitcherCommand(url: url) else { return }

        switch command.kind {
        case .any:
            handleAnySwitcherCommand(command)
        case .space:
            handle(command.action, with: spaceSwitcherController)
        case .window:
            handle(command.action, with: windowSwitcherController)
        case .allSpacesWindow:
            handle(command.action, with: allSpacesWindowSwitcherController)
        }
    }

    private func handle(_ action: SwitcherAction, with controller: any SwitcherControlling) {
        switch action {
        case .open:
            controller.openSwitcher()
        case .close, .cancel:
            controller.closeSwitcher()
        case .next:
            controller.moveSelectionForward()
        case .previous:
            controller.moveSelectionBackward()
        case .commit:
            controller.commitSwitcherSelection()
        case .select:
            break
        }
    }

    private func handleAnySwitcherCommand(_ command: SwitcherCommand) {
        switch command.action {
        case .close, .cancel:
            spaceSwitcherController.closeSwitcher()
            windowSwitcherController.closeSwitcher()
            allSpacesWindowSwitcherController.closeSwitcher()
        case .next:
            if windowSwitcherController.hasActiveSession {
                windowSwitcherController.moveSelectionForward()
            } else if allSpacesWindowSwitcherController.hasActiveSession {
                allSpacesWindowSwitcherController.moveSelectionForward()
            } else if spaceSwitcherController.hasActiveSession {
                spaceSwitcherController.moveSelectionForward()
            }
        case .previous:
            if windowSwitcherController.hasActiveSession {
                windowSwitcherController.moveSelectionBackward()
            } else if allSpacesWindowSwitcherController.hasActiveSession {
                allSpacesWindowSwitcherController.moveSelectionBackward()
            } else if spaceSwitcherController.hasActiveSession {
                spaceSwitcherController.moveSelectionBackward()
            }
        case .commit:
            if windowSwitcherController.hasActiveSession {
                windowSwitcherController.commitSwitcherSelection()
            } else if allSpacesWindowSwitcherController.hasActiveSession {
                allSpacesWindowSwitcherController.commitSwitcherSelection()
            } else if spaceSwitcherController.hasActiveSession {
                spaceSwitcherController.commitSwitcherSelection()
            }
        case .select:
            guard let index = command.index else { return }
            if windowSwitcherController.hasActiveSession {
                windowSwitcherController.commitSelection(at: index)
            } else if allSpacesWindowSwitcherController.hasActiveSession {
                allSpacesWindowSwitcherController.commitSelection(at: index)
            } else if spaceSwitcherController.hasActiveSession {
                spaceSwitcherController.commitSelection(at: index)
            }
        case .open:
            break
        }
    }
}
