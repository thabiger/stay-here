import AppKit
import Core

@MainActor
final class CompositionWindowManagers {
    let services: CompositionServices
    private let onAppearanceChange: () -> Void

    lazy var settingsWindowManager = SettingsWindowManager(
        settings: services.settings,
        appearanceManager: services.appearanceManager,
        onAppearanceChange: { [weak self] in
            self?.onAppearanceChange()
        },
        onOpenLogs: { [logger = services.logger] in openLogsInFinder(logger: logger) }
    )

    lazy var aboutWindowManager = AboutWindowManager(
        appearanceManager: services.appearanceManager
    )

    lazy var updateWindowManager = UpdateWindowManager(
        appearanceManager: services.appearanceManager
    )

    init(services: CompositionServices, onAppearanceChange: @escaping () -> Void) {
        self.services = services
        self.onAppearanceChange = onAppearanceChange
    }
}
