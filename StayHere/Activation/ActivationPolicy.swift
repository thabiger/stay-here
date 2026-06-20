import Foundation
import AppKit
import Core

public enum ActivationDecision: String {
    case launch
    case focusCurrentSpace
    case createNewWindow
    case singleWindowHint
    case switchToSingleWindowSpace
    case consumeOnly
    case passthrough
}

public struct ActivationContext {
    public let bundleID: String
    public let activeSpaceIDs: Set<Int>
    public let targetSpaceID: Int?
    public let appWindowSummary: AppWindowSummary?
    public let singleWindowSpaceID: Int?
    public let optionHeld: Bool

    public init(
        bundleID: String,
        activeSpaceIDs: Set<Int>,
        targetSpaceID: Int?,
        appWindowSummary: AppWindowSummary?,
        singleWindowSpaceID: Int?,
        optionHeld: Bool
    ) {
        self.bundleID = bundleID
        self.activeSpaceIDs = activeSpaceIDs
        self.targetSpaceID = targetSpaceID
        self.appWindowSummary = appWindowSummary
        self.singleWindowSpaceID = singleWindowSpaceID
        self.optionHeld = optionHeld
    }
}

public final class ActivationPolicy {
    private let isSingleWindowApp: (String) -> Bool
    private let isAppRunning: (String) -> Bool

    public convenience init(
        settings: ActivationSettings,
        isAppRunning: @escaping (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    ) {
        self.init(
            isSingleWindowApp: { bundleID in
                settings.activationSingleWindowAppBundleIDs.contains(bundleID)
            },
            isAppRunning: isAppRunning
        )
    }

    public init(
        isSingleWindowApp: @escaping (String) -> Bool = { _ in false },
        isAppRunning: @escaping (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
    ) {
        self.isSingleWindowApp = isSingleWindowApp
        self.isAppRunning = isAppRunning
    }

    public func decide(_ context: ActivationContext) -> ActivationDecision {
        guard isAppRunning(context.bundleID) else { return .launch }

        guard let summary = context.appWindowSummary else {
            return .passthrough
        }

        if summary.hasWindowOnTargetSpace {
            return .focusCurrentSpace
        }

        if isSingleWindowApp(context.bundleID) || summary.isSingleWindowCandidate {
            if context.optionHeld, context.singleWindowSpaceID == nil {
                return .passthrough
            }
            return context.optionHeld ? .switchToSingleWindowSpace : .singleWindowHint
        }

        return .createNewWindow
    }
}
