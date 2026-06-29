import AppKit
import Carbon
import Core
import OSLog

@MainActor
protocol AppCoordinating: AnyObject {
    func applicationDidFinishLaunching()
    func applicationWillTerminate()
    func handleIncomingURL(_ url: URL)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let retainedDependencyGraph: AnyObject?
    private let appCoordinator: any AppCoordinating

    private static let urlLogger = Logger(
        subsystem: "com.stayhere.StayHere",
        category: "url-scheme"
    )

    override init() {
        let compositionRoot = AppCompositionRoot(cgsBridge: CGSBridge.live)
        self.retainedDependencyGraph = compositionRoot // keep a reference to the composition root to prevent it from being deallocated
        self.appCoordinator = compositionRoot.runtimeCoordinator
        super.init()
    }

    /// This is used for testing purposes
    init(compositionRoot: AppCompositionRoot) {
        self.retainedDependencyGraph = compositionRoot
        self.appCoordinator = compositionRoot.runtimeCoordinator
        super.init()
    }

    /// This is used for testing purposes
    init(appCoordinator: any AppCoordinating) {
        self.retainedDependencyGraph = nil
        self.appCoordinator = appCoordinator
        super.init()
    }

    deinit {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        appCoordinator.applicationDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appCoordinator.applicationWillTerminate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            Self.urlLogger.info("Processing stayhere:// URL via Launch Services from frontmost app \(frontmostApp?.bundleIdentifier ?? "nil", privacy: .public): \(url.absoluteString, privacy: .public)")
            appCoordinator.handleIncomingURL(url)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        guard let senderPID = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value else {
            Self.urlLogger.error("Blocked stayhere:// URL from unknown sender (no PID in event): \(url.absoluteString, privacy: .public)")
            return
        }
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            Self.urlLogger.error("Blocked stayhere:// URL from PID \(senderPID) — no frontmost application")
            return
        }
        guard senderPID == frontmostPID else {
            if let senderApp = NSRunningApplication(processIdentifier: senderPID) {
                Self.urlLogger.error("Blocked stayhere:// URL from PID \(senderPID) (\(senderApp.bundleIdentifier ?? "?")), frontmost is PID \(frontmostPID)")
            } else {
                Self.urlLogger.error("Blocked stayhere:// URL from PID \(senderPID) (unknown app), frontmost is PID \(frontmostPID)")
            }
            return
        }

        Self.urlLogger.info("Accepted stayhere:// URL from frontmost app PID \(senderPID): \(url.absoluteString, privacy: .public)")
        appCoordinator.handleIncomingURL(url)
    }
}
