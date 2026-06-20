import AppKit
import Core

final class SwitcherCoordinator {
    private let spaceSwitcherController: any SwitcherControlling
    private let windowSwitcherController: any SwitcherControlling
    private let allSpacesWindowSwitcherController: any SwitcherControlling
    private let settings: SettingsRepository
    private let eventTapProxy: any EventTapProxying

    init(
        spaceSwitcherController: any SwitcherControlling,
        windowSwitcherController: any SwitcherControlling,
        allSpacesWindowSwitcherController: any SwitcherControlling,
        settings: SettingsRepository,
        eventTapProxy: any EventTapProxying
    ) {
        self.spaceSwitcherController = spaceSwitcherController
        self.windowSwitcherController = windowSwitcherController
        self.allSpacesWindowSwitcherController = allSpacesWindowSwitcherController
        self.settings = settings
        self.eventTapProxy = eventTapProxy
    }

    var hasActiveSession: Bool {
        windowSwitcherController.hasActiveSession
            || allSpacesWindowSwitcherController.hasActiveSession
            || spaceSwitcherController.hasActiveSession
    }

    func start() {
        registerIfEnabled(spaceSwitcherController, enabled: settings.spaceSwitcherEnabled)
        registerIfEnabled(windowSwitcherController, enabled: settings.windowSwitcherEnabled)
        registerIfEnabled(allSpacesWindowSwitcherController, enabled: settings.allSpacesWindowSwitcherEnabled)
    }

    func stop() {
        eventTapProxy.unregister(spaceSwitcherController)
        eventTapProxy.unregister(windowSwitcherController)
        eventTapProxy.unregister(allSpacesWindowSwitcherController)
        spaceSwitcherController.stop()
        windowSwitcherController.stop()
        allSpacesWindowSwitcherController.stop()
    }

    func syncControllers() {
        sync(spaceSwitcherController, enabled: settings.spaceSwitcherEnabled)
        sync(windowSwitcherController, enabled: settings.windowSwitcherEnabled)
        sync(allSpacesWindowSwitcherController, enabled: settings.allSpacesWindowSwitcherEnabled)
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

    private func sync(_ controller: any SwitcherControlling, enabled: Bool) {
        if enabled {
            registerIfEnabled(controller, enabled: true)
            controller.start()
        } else {
            eventTapProxy.unregister(controller)
            controller.stop()
        }
    }

    private func registerIfEnabled(_ controller: any SwitcherControlling, enabled: Bool) {
        guard enabled else { return }
        eventTapProxy.register(controller)
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
