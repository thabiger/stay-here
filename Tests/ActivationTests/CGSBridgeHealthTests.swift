import XCTest
@testable import Core

final class CGSBridgeHealthTests: XCTestCase {
    // MARK: - HealthReport.isHealthy aggregation

    func testIsHealthyWhenAllResolvedAndProbeSucceeded() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: true, role: .required),
                .init(symbol: "CGSCopyManagedDisplaySpaces", resolved: true, role: .required),
                .init(symbol: "CGSCopySpacesForWindows", resolved: true, role: .optional),
            ],
            payloadProbeSucceeded: true
        )
        XCTAssertTrue(report.isHealthy)
    }

    func testIsUnhealthyWhenCriticalSymbolMissing() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: false, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: true, role: .required),
                .init(symbol: "CGSCopyManagedDisplaySpaces", resolved: true, role: .required),
                .init(symbol: "CGSCopySpacesForWindows", resolved: true, role: .optional),
            ],
            payloadProbeSucceeded: true
        )
        XCTAssertFalse(report.isHealthy)
    }

    func testIsUnhealthyWhenRequiredSymbolMissing() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: false, role: .required),
                .init(symbol: "CGSCopyManagedDisplaySpaces", resolved: true, role: .required),
                .init(symbol: "CGSCopySpacesForWindows", resolved: true, role: .optional),
            ],
            payloadProbeSucceeded: true
        )
        XCTAssertFalse(report.isHealthy)
    }

    func testIsUnhealthyWhenProbeFailed() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: true, role: .required),
                .init(symbol: "CGSCopyManagedDisplaySpaces", resolved: true, role: .required),
                .init(symbol: "CGSCopySpacesForWindows", resolved: true, role: .optional),
            ],
            payloadProbeSucceeded: false
        )
        XCTAssertFalse(report.isHealthy)
    }

    func testIsHealthyWhenOnlyOptionalSymbolMissing() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: true, role: .required),
                .init(symbol: "CGSCopyManagedDisplaySpaces", resolved: true, role: .required),
                .init(symbol: "CGSCopySpacesForWindows", resolved: false, role: .optional),
            ],
            payloadProbeSucceeded: true
        )
        XCTAssertTrue(report.isHealthy)
    }

    // MARK: - HealthReport.degradedFeatureSummary

    func testDegradedSummaryAllResolved() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: true, role: .critical),
            ],
            payloadProbeSucceeded: true
        )
        XCTAssertEqual(report.degradedFeatureSummary, "all symbols resolved")
    }

    func testDegradedSummaryMissingSymbols() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
                .init(symbol: "_CGSDefaultConnection", resolved: false, role: .critical),
                .init(symbol: "CGSGetActiveSpace", resolved: false, role: .required),
            ],
            payloadProbeSucceeded: true
        )
        let summary = report.degradedFeatureSummary
        XCTAssertTrue(summary.contains("_CGSDefaultConnection"))
        XCTAssertTrue(summary.contains("CGSGetActiveSpace"))
    }

    func testDegradedSummaryProbeFailed() {
        let report = CGSBridge.HealthReport(
            symbols: [
                .init(symbol: "dlopen", resolved: true, role: .critical),
            ],
            payloadProbeSucceeded: false
        )
        XCTAssertTrue(report.degradedFeatureSummary.contains("payload probe failed"))
    }

    // MARK: - HealthReport.notApplicable

    func testNotApplicableIsHealthy() {
        XCTAssertTrue(CGSBridge.HealthReport.notApplicable.isHealthy)
    }

    func testNotApplicableHasEmptySymbols() {
        XCTAssertTrue(CGSBridge.HealthReport.notApplicable.symbols.isEmpty)
    }

    // MARK: - Default protocol extension

    func testDefaultBridgeHealthReturnsNotApplicable() {
        let mock = MockCGSBridge()
        XCTAssertEqual(mock.bridgeHealth(), .notApplicable)
    }

    // MARK: - CGSBridge.live in test environment

    func testLiveBridgeHealthInAutomationSession() {
        // In test environments, RuntimeEnvironment.isAutomationSession is true,
        // so bridgeHealth() returns .notApplicable immediately (no dlopen).
        XCTAssertEqual(CGSBridge.live.bridgeHealth(), .notApplicable)
    }
}
