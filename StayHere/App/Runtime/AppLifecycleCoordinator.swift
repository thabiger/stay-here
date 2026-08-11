import AppKit
import Foundation
import Core

struct AppSetupStatusSnapshot {
    let isSatisfied: Bool
    /// Permissions (Accessibility, Input Monitoring) — gates the safety-net
    /// refresh. Deliberately separate from `isSatisfied`: Mission Control
    /// shortcuts only gate in-app switching, not HUD/menu freshness for
    /// native switches (keyboard shortcut / Mission Control work regardless).
    let permissionsSatisfied: Bool
    let missingDescriptionsCount: Int
}

@MainActor
final class AppLifecycleCoordinator {
    private let applyAppearance: () -> Void
    private let setupStatusProvider: () -> AppSetupStatusSnapshot
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private let logger: any Logging
    private var pollTimer: Timer?
    private static let safetyNetTimerInterval: TimeInterval = 20

    init(
        appearanceManager: AppearanceManager,
        applyAppearance: (() -> Void)? = nil,
        setupStatusProvider: @escaping () -> AppSetupStatusSnapshot = {
            let status = StayHereSetupStatus.current()
            return AppSetupStatusSnapshot(
                isSatisfied: status.isSatisfied,
                permissionsSatisfied: status.permissions.isSatisfied,
                missingDescriptionsCount: status.missingDescriptions.count
            )
        },
        setActivationPolicy: @MainActor @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
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

        refreshSpacesAsync()
        rebuildSpaceItems()
        startSafetyNetTimer(isSettingsOpen: isSettingsOpen, refreshSpacesSoon: refreshSpacesSoon)
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

    func handleActiveSpaceChanged(
        isSettingsOpen: Bool,
        refreshSpacesConverging: @escaping () -> Void
    ) {
        guard !isSettingsOpen else { return }
        refreshSpacesConverging()
    }

    private func startSafetyNetTimer(
        isSettingsOpen: @escaping () -> Bool,
        refreshSpacesSoon: @escaping () -> Void
    ) {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.safetyNetTimerInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.safetyNetTick(isSettingsOpen: isSettingsOpen, refreshSpacesSoon: refreshSpacesSoon)
            }
        }
    }

    func safetyNetTick(
        isSettingsOpen: () -> Bool,
        refreshSpacesSoon: () -> Void
    ) {
        guard !isSettingsOpen() else { return }
        // Gate on permissions only, not Mission Control shortcut configuration.
        // A user who switches natively (Ctrl+Arrow / Mission Control) without
        // enabling the "Switch to Desktop N" shortcuts still needs the fallback
        // refresh to keep the bar/HUD state fresh when a notification is missed.
        guard setupStatusProvider().permissionsSatisfied else { return }
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
