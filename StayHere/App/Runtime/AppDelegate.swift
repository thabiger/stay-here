import AppKit
import Carbon
import Core

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

    override init() {
        let compositionRoot = AppCompositionRoot()
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
            appCoordinator.handleIncomingURL(url)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        appCoordinator.handleIncomingURL(url)
    }
}
