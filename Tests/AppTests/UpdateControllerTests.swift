import XCTest
import Core
@testable import StayHereApp

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testManualCheckShowsUpToDateMessageWhenNoUpdateExists() async {
        let service = UpdateServiceSpy()
        service.nextResult = .noUpdate
        let windowManager = UpdateWindowManagerSpy()
        let settings = UserDefaultsSettingsRepository()
        var upToDateMessageCount = 0
        let controller = UpdateController(
            settings: settings,
            updateService: service,
            updateWindowManager: windowManager,
            appearanceManager: AppearanceManager(settings: settings),
            setAvailableUpdate: { _ in },
            openURL: { _ in true },
            activateApp: {},
            setActivationPolicy: { _ in },
            presentUpToDateMessage: { upToDateMessageCount += 1 },
            presentUpdateErrorMessage: { _ in }
        )

        controller.performManualCheck()
        await waitForAsyncWork()

        XCTAssertEqual(upToDateMessageCount, 1)
        XCTAssertEqual(windowManager.showCount, 0)
    }

    func testManualCheckPresentsUpdateWindowWhenUpdateExists() async {
        let service = UpdateServiceSpy()
        let updateInfo = Self.makeUpdateInfo(version: "0.2.0")
        service.nextResult = .updateAvailable(updateInfo)
        let windowManager = UpdateWindowManagerSpy()
        let settings = UserDefaultsSettingsRepository()
        let controller = UpdateController(
            settings: settings,
            updateService: service,
            updateWindowManager: windowManager,
            appearanceManager: AppearanceManager(settings: settings),
            setAvailableUpdate: { _ in },
            openURL: { _ in true },
            activateApp: {},
            setActivationPolicy: { _ in },
            presentUpToDateMessage: {},
            presentUpdateErrorMessage: { _ in }
        )

        controller.performManualCheck()
        await waitForAsyncWork()

        XCTAssertEqual(windowManager.showCount, 1)
        XCTAssertEqual(windowManager.lastUpdateInfo, updateInfo)
    }

    func testAutomaticCheckShowsUpdateWindowOnlyOncePerVersion() async {
        let service = UpdateServiceSpy()
        let updateInfo = Self.makeUpdateInfo(version: "0.2.0")
        service.nextResult = .updateAvailable(updateInfo)
        let windowManager = UpdateWindowManagerSpy()
        let settings = UserDefaultsSettingsRepository()
        let controller = UpdateController(
            settings: settings,
            updateService: service,
            updateWindowManager: windowManager,
            appearanceManager: AppearanceManager(settings: settings),
            setAvailableUpdate: { _ in },
            openURL: { _ in true },
            activateApp: {},
            setActivationPolicy: { _ in },
            presentUpToDateMessage: {},
            presentUpdateErrorMessage: { _ in }
        )

        controller.scheduleAutomaticCheck()
        await waitForAsyncWork()
        controller.scheduleAutomaticCheck()
        await waitForAsyncWork()

        XCTAssertEqual(windowManager.showCount, 1)
    }

    func testManualCheckShowsErrorMessageWhenRequestFails() async {
        let service = UpdateServiceSpy()
        service.nextError = UpdateCheckError.unexpectedStatusCode(404, "Not Found")
        let windowManager = UpdateWindowManagerSpy()
        let settings = UserDefaultsSettingsRepository()
        var shownError: String?
        let controller = UpdateController(
            settings: settings,
            updateService: service,
            updateWindowManager: windowManager,
            appearanceManager: AppearanceManager(settings: settings),
            setAvailableUpdate: { _ in },
            openURL: { _ in true },
            activateApp: {},
            setActivationPolicy: { _ in },
            presentUpToDateMessage: {},
            presentUpdateErrorMessage: { shownError = $0 }
        )

        controller.performManualCheck()
        await waitForAsyncWork()

        XCTAssertNotNil(shownError)
        XCTAssertTrue(shownError?.contains("404") == true)
    }

    private func waitForAsyncWork() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private static func makeUpdateInfo(version: String) -> UpdateInfo {
        UpdateInfo(
            version: version,
            releaseURL: URL(string: "https://example.com/release")!,
            downloadURL: URL(string: "https://example.com/download")!,
            title: "StayHere \(version)",
            notes: "Release notes",
            publishedAt: Date()
        )
    }
}

private final class UpdateServiceSpy: UpdateService {
    var cachedInfo: UpdateInfo?
    var nextResult: UpdateCheckResult = .noUpdate
    var nextError: Error?

    func cachedUpdateInfo() async -> UpdateInfo? {
        cachedInfo
    }

    func checkForUpdates(force: Bool) async throws -> UpdateCheckResult {
        if let nextError {
            throw nextError
        }
        return nextResult
    }
}

@MainActor
private final class UpdateWindowManagerSpy: UpdateWindowManaging {
    private(set) var showCount = 0
    private(set) var lastUpdateInfo: UpdateInfo?

    func showUpdate(
        _ updateInfo: UpdateInfo,
        onDownload: @escaping () -> Void,
        onViewReleaseNotes: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        showCount += 1
        lastUpdateInfo = updateInfo
    }

    func close() {}
}
