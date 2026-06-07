import Foundation
import AppKit

public final class Logger {
    public static let shared = Logger()

    private let queue = DispatchQueue(label: "stayhere.logger")
    private let logURL: URL
    private let iso = ISO8601DateFormatter()
    private let settings: SettingsRepository

    public convenience init() {
        self.init(settings: UserDefaultsSettingsRepository())
    }

    public init(settings: SettingsRepository) {
        self.settings = settings
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StayHere", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("stayhere.log")
    }

    public func info(_ message: String) {
        guard settings.diagnosticsEnabled else { return }
        write("INFO", message)
    }

    public func error(_ message: String) {
        write("ERROR", message)
    }

    public func flush() {
        queue.sync {}
    }

    public func openLogsInFinder() {
        let url = logURL.deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    private func write(_ level: String, _ message: String) {
        queue.async {
            let line = "[\(self.iso.string(from: Date()))] [\(level)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logURL.path),
                   let handle = try? FileHandle(forWritingTo: self.logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: self.logURL)
                }
            }
        }
    }
}
