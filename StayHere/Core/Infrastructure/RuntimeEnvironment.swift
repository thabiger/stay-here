import Foundation

public enum RuntimeEnvironment {
    public static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil {
            return true
        }

        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        return Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }

    public static var isContinuousIntegration: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    public static var isAutomationSession: Bool {
        isContinuousIntegration || isRunningTests
    }
}
