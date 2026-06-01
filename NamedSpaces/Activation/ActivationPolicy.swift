import Foundation
import AppKit
import Core

public enum ActivationDecision: String {
    case launch
    case focusCurrentSpace
    case createNewWindow
    case moveSingleWindow
    case passthrough
}

public struct ActivationContext {
    public let bundleID: String
    public let activeSpaceIDs: Set<Int>
    public let targetSpaceID: Int?
    public let appWindowSummary: AppWindowSummary?

    public init(bundleID: String, activeSpaceIDs: Set<Int>, targetSpaceID: Int?, appWindowSummary: AppWindowSummary?) {
        self.bundleID = bundleID
        self.activeSpaceIDs = activeSpaceIDs
        self.targetSpaceID = targetSpaceID
        self.appWindowSummary = appWindowSummary
    }
}

public final class ActivationPolicy {
    private let moveWindowPreferredBundles: Set<String> = [
        "com.apple.Notes"
    ]

    public init() {}

    public func decide(_ context: ActivationContext) -> ActivationDecision {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleID)
        guard !apps.isEmpty else { return .launch }

        guard let summary = context.appWindowSummary else {
            return .focusCurrentSpace
        }

        if summary.hasWindowOnTargetSpace {
            return .focusCurrentSpace
        }

        if moveWindowPreferredBundles.contains(context.bundleID) {
            return .moveSingleWindow
        }

        if summary.isSingleWindowCandidate {
            return .moveSingleWindow
        }

        return .createNewWindow
    }
}
