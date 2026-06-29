import AppKit
import Core

func openLogsInFinder(logger: Logging) {
    NSWorkspace.shared.open(logger.logsDirectory)
}
