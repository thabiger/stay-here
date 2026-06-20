import AppKit
import Foundation
import Core

struct AppSetupStatusSnapshot {
    let isSatisfied: Bool
    let missingDescriptionsCount: Int
}

final class AppLifecycleCoordinator {
    private let applyAppearance: () -> Void
    private let setupStatusProvider: () -> AppSetupStatusSnapshot
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let logger: any Logging
    private var pollTimer: Timer?

    init(
        appearanceManager: AppearanceManager,
        applyAppearance: (() -> Void)? = nil,
        setupStatusProvider: @escaping () -> AppSetupStatusSnapshot = {
            let status = StayHereSetupStatus.current()
            return AppSetupStatusSnapshot(
                isSatisfied: status.isSatisfied,
                missingDescriptionsCount: status.missingDescriptions.count
            )
        },
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
        logger: any Logging
    ) {
        self.applyAppearance = applyAppearance ?? { appearanceManager.applyCurrentMode() }
        self.setupStatusProvider = setupStatusProvider
        self.setActivationPolicy = setActivationPolicy
        self.logger = logger
    }

    func applicationDidFinishLaunching(
        isSettingsOpen: @escaping () -> Bool,
        refreshSpacesSoon: @escaping () -> Void,
        refreshSpacesAsync: @escaping () -> Void,
        rebuildSpaceItems: @escaping () -> Void,
        startEventDrivenControllers: @escaping () -> Void,
        presentSetupRequirementsWarning: @escaping () -> Void
    ) {
        setActivationPolicy(.accessory) // set the app to accessory mode (hidden in the Dock)
        applyAppearance() // light/dark mode

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard !isSettingsOpen() else { return }
            refreshSpacesSoon()
        }

        refreshSpacesAsync()
        rebuildSpaceItems()
        showSetupRequirementsIfNeeded(
            startEventDrivenControllers: startEventDrivenControllers,
            presentSetupRequirementsWarning: presentSetupRequirementsWarning
        )
    }

    func applicationWillTerminate(stopControllers: @escaping () -> Void) {
        logger.info("application will terminate")
        logger.flush()
        pollTimer?.invalidate()
        pollTimer = nil
        stopControllers()
    }

    func handleActiveSpaceChanged(isSettingsOpen: Bool, refreshSpacesSoon: @escaping () -> Void) {
        guard !isSettingsOpen else { return }
        refreshSpacesSoon()
    }

    private func showSetupRequirementsIfNeeded(
        startEventDrivenControllers: @escaping () -> Void,
        presentSetupRequirementsWarning: @escaping () -> Void
    ) {
        let status = setupStatusProvider()
        guard !status.isSatisfied else {
            startEventDrivenControllers()
            return
        }

        logger.error("setup requirements missing count=\(status.missingDescriptionsCount)")
        presentSetupRequirementsWarning()
    }
}
