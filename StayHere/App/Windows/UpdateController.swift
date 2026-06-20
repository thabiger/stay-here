import AppKit
import Core

@MainActor
protocol UpdateControlling: AnyObject {
    func restoreCachedState()
    func scheduleAutomaticCheck()
    func performManualCheck()
    func presentAvailableUpdate()
}

@MainActor
final class UpdateController: UpdateControlling {
    private let settings: UpdateSettings
    private let updateService: any UpdateService
    private let updateWindowManager: any UpdateWindowManaging
    private let setAvailableUpdate: (UpdateInfo?) -> Void
    private let openURL: (URL) -> Bool
    private let presentUpToDateMessage: () -> Void
    private let presentUpdateErrorMessage: (String) -> Void
    private let logger: any Logging

    private var currentUpdateInfo: UpdateInfo?
    private var announcedVersions: Set<String> = []
    private var automaticCheckTask: Task<Void, Never>?

    init(
        settings: UpdateSettings,
        updateService: any UpdateService,
        updateWindowManager: any UpdateWindowManaging,
        appearanceManager: AppearanceManager,
        setAvailableUpdate: @escaping (UpdateInfo?) -> Void,
        openURL: ((URL) -> Bool)? = nil,
        activateApp: (() -> Void)? = nil,
        setActivationPolicy: ((NSApplication.ActivationPolicy) -> Void)? = nil,
        presentUpToDateMessage: (() -> Void)? = nil,
        presentUpdateErrorMessage: ((String) -> Void)? = nil,
        logger: any Logging
    ) {
        self.settings = settings
        self.updateService = updateService
        self.updateWindowManager = updateWindowManager
        self.setAvailableUpdate = setAvailableUpdate
        self.openURL = openURL ?? { NSWorkspace.shared.open($0) }
        let activateApp = activateApp ?? { NSApp.activate(ignoringOtherApps: true) }
        let setActivationPolicy = setActivationPolicy ?? { NSApp.setActivationPolicy($0) }
        self.presentUpToDateMessage = presentUpToDateMessage ?? { [weak appearanceManager] in
            guard let appearanceManager else { return }
            setActivationPolicy(.regular)
            activateApp()

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "You’re up to date"
            alert.informativeText = "StayHere is already running the latest available version."
            alert.addButton(withTitle: "OK")
            appearanceManager.applyCurrentMode(to: [alert.window])
            _ = alert.runModal()
        }
        self.presentUpdateErrorMessage = presentUpdateErrorMessage ?? { [weak appearanceManager] message in
            guard let appearanceManager else { return }
            setActivationPolicy(.regular)
            activateApp()

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Update Check Failed"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            appearanceManager.applyCurrentMode(to: [alert.window])
            _ = alert.runModal()
        }
        self.logger = logger
    }

    func restoreCachedState() {
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            guard let self else { return }
            let cachedUpdate = await self.updateService.cachedUpdateInfo()
            await MainActor.run {
                self.applyUpdateInfo(cachedUpdate)
            }
        }
    }

    func scheduleAutomaticCheck() {
        guard settings.automaticUpdateChecksEnabled else { return }

        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.updateService.checkForUpdates(force: false)
                await MainActor.run {
                    self.handle(result: result, source: .automatic)
                }
            } catch {
                logger.info("automatic update check failed: \(error.localizedDescription)")
            }
        }
    }

    func performManualCheck() {
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.updateService.checkForUpdates(force: true)
                await MainActor.run {
                    self.handle(result: result, source: .manual)
                }
            } catch {
                logger.info("manual update check failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.presentUpdateErrorMessage(error.localizedDescription)
                }
            }
        }
    }

    func presentAvailableUpdate() {
        guard let currentUpdateInfo else {
            performManualCheck()
            return
        }
        presentUpdateWindow(for: currentUpdateInfo)
    }

    private func handle(result: UpdateCheckResult, source: UpdateSource) {
        switch result {
        case .noUpdate:
            applyUpdateInfo(nil)
            if source == .manual {
                presentUpToDateMessage()
            }
        case .updateAvailable(let updateInfo):
            applyUpdateInfo(updateInfo)
            if source == .automatic {
                announceUpdateIfNeeded(updateInfo)
            } else {
                presentUpdateWindow(for: updateInfo)
            }
        }
    }

    private func applyUpdateInfo(_ updateInfo: UpdateInfo?) {
        currentUpdateInfo = updateInfo
        setAvailableUpdate(updateInfo)
        if updateInfo == nil {
            updateWindowManager.close()
        }
    }

    private func announceUpdateIfNeeded(_ updateInfo: UpdateInfo) {
        guard announcedVersions.insert(updateInfo.version).inserted else { return }
        presentUpdateWindow(for: updateInfo)
    }

    private func presentUpdateWindow(for updateInfo: UpdateInfo) {
        updateWindowManager.showUpdate(
            updateInfo,
            onDownload: { [weak self] in
                guard let self else { return }
                _ = self.openURL(updateInfo.downloadURL)
                self.updateWindowManager.close()
            },
            onViewReleaseNotes: { [weak self] in
                guard let self else { return }
                _ = self.openURL(updateInfo.releaseURL)
            },
            onLater: { [weak self] in
                self?.updateWindowManager.close()
            }
        )
    }

    private enum UpdateSource {
        case automatic
        case manual
    }
}
