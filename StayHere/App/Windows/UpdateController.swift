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
    private let alertPresenter: any UpdateAlertPresenting
    private let logger: any Logging

    private var currentUpdateInfo: UpdateInfo?
    private var announcedVersions: Set<String> = []
    private var automaticCheckTask: Task<Void, Never>?

    init(
        settings: UpdateSettings,
        updateService: any UpdateService,
        updateWindowManager: any UpdateWindowManaging,
        alertPresenter: any UpdateAlertPresenting,
        setAvailableUpdate: @escaping (UpdateInfo?) -> Void,
        openURL: ((URL) -> Bool)? = nil,
        logger: any Logging
    ) {
        self.settings = settings
        self.updateService = updateService
        self.updateWindowManager = updateWindowManager
        self.alertPresenter = alertPresenter
        self.setAvailableUpdate = setAvailableUpdate
        self.openURL = openURL ?? { NSWorkspace.shared.open($0) }
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
                    self.alertPresenter.presentErrorAlert(message: error.localizedDescription)
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
                alertPresenter.presentUpToDateAlert()
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
                if isTrustedHost(updateInfo.downloadURL) {
                    _ = self.openURL(updateInfo.downloadURL)
                } else {
                    logger.error("Blocked attempt to open download URL with untrusted host: \(updateInfo.downloadURL.absoluteString)")
                }
                self.updateWindowManager.close()
            },
            onViewReleaseNotes: { [weak self] in
                guard let self else { return }
                if isTrustedHost(updateInfo.releaseURL) {
                    _ = self.openURL(updateInfo.releaseURL)
                } else {
                    logger.error("Blocked attempt to open release notes URL with untrusted host: \(updateInfo.releaseURL.absoluteString)")
                }
            },
            onLater: { [weak self] in
                self?.updateWindowManager.close()
            }
        )
    }

    private func isTrustedHost(_ url: URL) -> Bool {
        url.host == "github.com"
    }

    private enum UpdateSource {
        case automatic
        case manual
    }
}
