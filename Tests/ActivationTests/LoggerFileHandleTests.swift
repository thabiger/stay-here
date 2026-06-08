import XCTest
import Core
@testable import Core

final class LoggerFileHandleTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggerFileHandleTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeLogger(
        diagnosticsEnabled: Bool = true,
        logURL: URL? = nil
    ) -> Logger {
        let settings = MockSettingsRepository()
        settings.diagnosticsEnabled = diagnosticsEnabled
        return Logger(
            settings: settings,
            logURL: logURL ?? tempDir.appendingPathComponent("stayhere.log")
        )
    }

    // MARK: - P3: persistent file handle

    /// P3: the file handle is opened once in init and reused across
    /// writes. The previous implementation opened/closed a handle on
    /// every log call (1–5 ms each); the cached handle is the perf win.
    func testFileHandleIsOpenedOnceInInit() {
        let logger = makeLogger()
        XCTAssertNotNil(logger.testFileHandle, "File handle must be opened in init")
    }

    /// P3: the same file handle instance is reused for every write.
    /// We verify reference equality (===) across multiple writes to
    /// prove the logger does not close and re-open the handle per call.
    func testFileHandleIsReusedAcrossWrites() {
        let logger = makeLogger()
        let handleBefore = logger.testFileHandle
        XCTAssertNotNil(handleBefore)

        logger.info("first")
        logger.info("second")
        logger.info("third")
        logger.flush()

        let handleAfter = logger.testFileHandle
        XCTAssertTrue(
            handleBefore === handleAfter,
            "File handle must be the same instance across writes"
        )
    }

    // MARK: - S5: file permissions

    /// S5: a new log file must be created with 0o600 (owner read/write
    /// only) so other users on the system cannot read it.
    func testNewLogFileIsCreatedWithOwnerOnlyPermissions() throws {
        let logURL = tempDir.appendingPathComponent("newfile.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))

        _ = makeLogger(logURL: logURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(perms, 0o600, "New log file must be 0o600 (owner-only)")
    }

    /// S5: an existing log file from a prior app version with looser
    /// permissions must be tightened to 0o600 on init.
    func testExistingLogFilePermissionsAreTightenedToOwnerOnly() throws {
        let logURL = tempDir.appendingPathComponent("oldfile.log")
        FileManager.default.createFile(
            atPath: logURL.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: 0o644 as UInt16)]
        )

        // Confirm the test fixture really did start at 0o644.
        let preAttrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let prePerms = (preAttrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(prePerms, 0o644, "fixture: starting perms should be 0o644")

        _ = makeLogger(logURL: logURL)

        let postAttrs = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let postPerms = (postAttrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(postPerms, 0o600, "Existing log file must be tightened to 0o600")
    }

    /// S5: the parent directory must be created with 0o700 so other
    /// users on the system cannot list the log directory contents.
    func testLogDirectoryIsCreatedWithOwnerOnlyPermissions() throws {
        let logsDir = tempDir.appendingPathComponent("StayHere", isDirectory: true)
        let logURL = logsDir.appendingPathComponent("stayhere.log")

        XCTAssertFalse(FileManager.default.fileExists(atPath: logsDir.path))
        _ = makeLogger(logURL: logURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: logsDir.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(perms, 0o700, "Log directory must be 0o700 (owner-only)")
    }

    // MARK: - Behaviour: writes are persisted and gated

    /// Writes via the persistent handle must end up in the file.
    func testInfoWritesArePersistedToFile() throws {
        let logURL = tempDir.appendingPathComponent("persisted.log")
        let logger = makeLogger(logURL: logURL)

        logger.info("hello world")
        logger.flush()

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("hello world"), "info message must be persisted")
        XCTAssertTrue(content.contains("INFO"), "log level must be persisted")
    }

    /// `error` writes are NOT gated by the diagnostics flag — they
    /// always go to the file, even when diagnostics are disabled.
    func testErrorWritesAreAlwaysPersisted() throws {
        let logURL = tempDir.appendingPathComponent("errors.log")
        let logger = makeLogger(diagnosticsEnabled: false, logURL: logURL)

        logger.error("something broke")
        logger.flush()

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("something broke"), "error message must be persisted")
        XCTAssertTrue(content.contains("ERROR"), "log level must be persisted")
    }

    /// `info` writes are gated by `diagnosticsEnabled` and skipped
    /// when diagnostics are off — no file is created.
    func testInfoWritesAreSkippedWhenDiagnosticsDisabled() throws {
        let logURL = tempDir.appendingPathComponent("disabled.log")
        let logger = makeLogger(diagnosticsEnabled: false, logURL: logURL)

        logger.info("should be skipped")
        logger.flush()

        // The init created the file, but no info lines should be in it.
        let content = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(content.contains("should be skipped"), "info must be skipped when diagnostics are off")
    }

    /// Multiple writes accumulate in the file in order.
    func testMultipleWritesAccumulateInOrder() throws {
        let logURL = tempDir.appendingPathComponent("multi.log")
        let logger = makeLogger(logURL: logURL)

        logger.info("alpha")
        logger.info("beta")
        logger.info("gamma")
        logger.flush()

        let content = try String(contentsOf: logURL, encoding: .utf8)
        let alphaRange = content.range(of: "alpha")
        let betaRange = content.range(of: "beta")
        let gammaRange = content.range(of: "gamma")
        XCTAssertNotNil(alphaRange)
        XCTAssertNotNil(betaRange)
        XCTAssertNotNil(gammaRange)
        XCTAssertTrue(alphaRange!.lowerBound < betaRange!.lowerBound)
        XCTAssertTrue(betaRange!.lowerBound < gammaRange!.lowerBound)
    }
}
