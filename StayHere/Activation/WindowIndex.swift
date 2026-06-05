import Foundation
import CoreGraphics
import AppKit
import Core

public struct IndexedWindow {
    public let windowID: Int
    public let pid: pid_t
    public let bundleID: String?
    public let isOnScreen: Bool
    public let layer: Int
    public let spaceIDs: [Int]
}

public struct AppWindowSummary {
    public let bundleID: String
    public let pid: pid_t
    public let windowsOnCurrentSpace: [IndexedWindow]
    public let windowsOnTargetSpace: [IndexedWindow]
    public let allWindows: [IndexedWindow]

    public var hasWindowOnCurrentSpace: Bool { !windowsOnCurrentSpace.isEmpty }
    public var hasWindowOnTargetSpace: Bool { !windowsOnTargetSpace.isEmpty }
    public var totalWindowCount: Int { allWindows.count }
    public var isSingleWindowCandidate: Bool { allWindows.count <= 1 }
}

public final class WindowIndex {
    public init() {}

    public func summarize(bundleID: String, activeSpaceIDs: Set<Int>, targetSpaceID: Int?) -> AppWindowSummary? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        let pid = app.processIdentifier
        let all = fetchWindows(for: pid, options: [.optionAll])
        let current = all.filter { !activeSpaceIDs.isDisjoint(with: Set($0.spaceIDs)) }
        let target = targetSpaceID.map { targetID in
            all.filter { $0.spaceIDs.contains(targetID) }
        } ?? []
        return AppWindowSummary(
            bundleID: bundleID,
            pid: pid,
            windowsOnCurrentSpace: current,
            windowsOnTargetSpace: target,
            allWindows: all
        )
    }

    private func fetchWindows(for pid: pid_t, options: CGWindowListOption) -> [IndexedWindow] {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { item in
            guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == pid,
                  let windowNumber = item[kCGWindowNumber as String] as? NSNumber,
                  let layer = item[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0 else {
                return nil
            }

            let onScreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            if let bounds = item[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat,
               (width <= 1 || height <= 1) {
                return nil
            }

            return IndexedWindow(
                windowID: windowNumber.intValue,
                pid: pid,
                bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                isOnScreen: onScreen,
                layer: layer.intValue,
                spaceIDs: CGSBridge.spacesForWindow(windowID: windowNumber.intValue)
            )
        }
    }
}
