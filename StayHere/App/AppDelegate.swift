import AppKit
import Core

@MainActor
protocol AppCoordinating: AnyObject {
    func applicationDidFinishLaunching()
    func applicationWillTerminate()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let retainedDependencyGraph: AnyObject?
    private let appCoordinator: any AppCoordinating

    override init() {
        let compositionRoot = AppCompositionRoot()
        self.retainedDependencyGraph = compositionRoot
        self.appCoordinator = compositionRoot.runtimeCoordinator
        super.init()
    }

    init(compositionRoot: AppCompositionRoot) {
        self.retainedDependencyGraph = compositionRoot
        self.appCoordinator = compositionRoot.runtimeCoordinator
        super.init()
    }

    init(appCoordinator: any AppCoordinating) {
        self.retainedDependencyGraph = nil
        self.appCoordinator = appCoordinator
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appCoordinator.applicationDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appCoordinator.applicationWillTerminate()
    }
}
