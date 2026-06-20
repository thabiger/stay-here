@preconcurrency import Foundation

/// Process-local logging interface. Implementations are responsible for
/// their own concurrency isolation.
public protocol Logging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
    func flush()
    var logsDirectory: URL { get }
}

/// A logger that discards every message. Useful for tests and for
/// production paths that must not emit diagnostics.
public struct NoOpLogger: Logging {
    public init() {}

    public func info(_ message: String) {}
    public func error(_ message: String) {}
    public func flush() {}
    public var logsDirectory: URL { FileManager.default.temporaryDirectory }
}

/// File-backed logger that keeps a single persistent `FileHandle` open for
/// the lifetime of the instance.
///
/// - `error(_:)` is always written.
/// - `info(_:)` is written only when `isInfoEnabled()` returns `true`.
/// - All writes are serialized on an internal queue.
public final class FileLogger: Logging, @unchecked Sendable {
    private let queue = DispatchQueue(label: "stayhere.logger")
    private let logURL: URL
    /// Persistent file handle opened in `init` and kept open for the
    /// lifetime of the logger. P3 perf fix: replaces the previous
    /// open/seek/close cycle that ran on every log write (1–5 ms each).
    private let fileHandle: FileHandle?
    private let iso = ISO8601DateFormatter()
    private let isInfoEnabled: () -> Bool

    public convenience init(
        isInfoEnabled: @escaping () -> Bool,
        logsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StayHere", isDirectory: true)
    ) {
        let url = logsDirectory.appendingPathComponent("stayhere.log")
        self.init(isInfoEnabled: isInfoEnabled, logURL: url)
    }

    public init(isInfoEnabled: @escaping () -> Bool, logURL: URL) {
        self.isInfoEnabled = isInfoEnabled
        self.logURL = logURL

        // S5: create the parent directory with owner-only permissions
        // (or tighten the permissions on an existing directory from a
        // prior app version). Idempotent.
        let parentDir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700 as UInt16)]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700 as UInt16)],
            ofItemAtPath: parentDir.path
        )

        // S5: create the log file with owner-only permissions, or
        // tighten the permissions on an existing file. Idempotent.
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: 0o600 as UInt16)]
            )
        } else {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600 as UInt16)],
                ofItemAtPath: logURL.path
            )
        }

        // P3: open a single persistent handle for the lifetime of the
        // logger. seekToEnd once so the cursor is at the existing
        // tail before the first write.
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            self.fileHandle = handle
        } else {
            self.fileHandle = nil
        }
    }

    deinit {
        // Capture locally so the deinit closure does not retain `self`
        // and trigger the `queue.sync` from the queue's own thread.
        let handle = fileHandle
        queue.sync {
            try? handle?.close()
        }
    }

    public func info(_ message: String) {
        guard isInfoEnabled() else { return }
        write("INFO", message)
    }

    public func error(_ message: String) {
        write("ERROR", message)
    }

    public func flush() {
        queue.sync {}
    }

    public var logsDirectory: URL { logURL.deletingLastPathComponent() }

    /// Test seam — exposes the persistent file handle so tests can
    /// verify it is opened once in init and reused across writes (P3).
    internal var testFileHandle: FileHandle? { fileHandle }

    /// Test seam — exposes the log URL so tests can verify file
    /// creation and permissions (S5).
    internal var testLogURL: URL { logURL }

    private func write(_ level: String, _ message: String) {
        queue.async { [fileHandle] in
            let line = "[\(self.iso.string(from: Date()))] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            try? fileHandle?.write(contentsOf: data)
        }
    }
}
