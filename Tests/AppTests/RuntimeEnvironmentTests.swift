import XCTest
import Core

final class RuntimeEnvironmentTests: XCTestCase {
    func testAutomationSessionIsEnabledUnderXCTest() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests)
        XCTAssertTrue(RuntimeEnvironment.isAutomationSession)
    }
}
