import Foundation
import AppKit
import CoreGraphics

public final class ShortcutPoster {
    private let runningApplications: (String) -> [any RunningApplicationControlling]
    private let postNewWindowShortcut: (pid_t) -> Bool

    public init(
        runningApplications: @escaping (String) -> [any RunningApplicationControlling] = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        },
        postNewWindowShortcut: @escaping (pid_t) -> Bool = ShortcutPoster.defaultPostNewWindowShortcut
    ) {
        self.runningApplications = runningApplications
        self.postNewWindowShortcut = postNewWindowShortcut
    }

    @discardableResult
    public func sendNewWindowShortcut(toBundleID bundleID: String) -> Bool {
        guard let app = runningApplications(bundleID).first else { return false }
        return postNewWindowShortcut(app.processIdentifier)
    }

    public static func defaultPostNewWindowShortcut(processIdentifier: pid_t) -> Bool {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 45, keyDown: false)
        up?.flags = .maskCommand
        guard let down, let up else { return false }
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }
}
