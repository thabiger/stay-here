import XCTest
@testable import StayHereApp

final class MacOSPermissionCheckTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(nil)
    }

    // MARK: - Pre-macOS-26 path (Input Monitoring required)

    func testIsSatisfiedRequiresBothPermissions() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let onlyAccessibility = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertFalse(onlyAccessibility.isSatisfied)

        let onlyInputMonitoring = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        XCTAssertFalse(onlyInputMonitoring.isSatisfied)

        let neither = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        XCTAssertFalse(neither.isSatisfied)

        let both = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        XCTAssertTrue(both.isSatisfied)
    }

    func testMissingPermissionNamesIncludesInputMonitoring() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(status.missingPermissionNames, ["Input Monitoring"])
    }

    func testMissingPermissionNamesIncludesAccessibility() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        XCTAssertEqual(status.missingPermissionNames, ["Accessibility"])
    }

    func testMissingPermissionNamesIncludesBothWhenNeitherGranted() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(
            status.missingPermissionNames,
            ["Accessibility", "Input Monitoring"]
        )
    }

    func testMissingPermissionNamesIsEmptyWhenBothGranted() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        XCTAssertTrue(status.missingPermissionNames.isEmpty)
    }

    func testCurrentStatusBothInjectedClosuresDenyingReturnsUnsatisfied() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionCheck.currentStatus(
            isAccessibilityTrusted: { false },
            isInputMonitoringGranted: { false }
        )
        XCTAssertFalse(status.isSatisfied)
        XCTAssertEqual(
            status.missingPermissionNames,
            ["Accessibility", "Input Monitoring"]
        )
    }

    // MARK: - macOS 26+ (Tahoe) path — Input Monitoring not required

    func testIsSatisfiedOnTahoeRequiresOnlyAccessibility() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertTrue(status.isSatisfied, "On macOS 26+ Input Monitoring is irrelevant")
    }

    func testIsSatisfiedOnTahoeStillRequiresAccessibility() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let status = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        XCTAssertFalse(status.isSatisfied, "Accessibility is always required")
    }

    func testMissingPermissionNamesOnTahoeIgnoresInputMonitoring() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertTrue(status.missingPermissionNames.isEmpty)
    }

    func testMissingPermissionNamesOnTahoeStillListsAccessibility() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let status = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        XCTAssertEqual(status.missingPermissionNames, ["Accessibility"])
    }

    func testCurrentStatusOnTahoeWithAccessibilityGrantedIsSatisfied() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let status = MacOSPermissionCheck.currentStatus(
            isAccessibilityTrusted: { true },
            isInputMonitoringGranted: { false }
        )
        XCTAssertTrue(status.isSatisfied)
    }

    // MARK: - Enum metadata

    func testMacOSPermissionKindAccessibilityDisplayName() {
        XCTAssertEqual(MacOSPermissionKind.accessibility.displayName, "Accessibility")
    }

    func testMacOSPermissionKindInputMonitoringDisplayName() {
        XCTAssertEqual(MacOSPermissionKind.inputMonitoring.displayName, "Input Monitoring")
    }

    func testMacOSPermissionKindAccessibilitySettingsPane() {
        XCTAssertEqual(
            MacOSPermissionKind.accessibility.settingsPane,
            "Privacy_Accessibility"
        )
    }

    func testMacOSPermissionKindInputMonitoringSettingsPane() {
        XCTAssertEqual(
            MacOSPermissionKind.inputMonitoring.settingsPane,
            "Privacy_ListenEvent"
        )
    }

    func testMacOSPermissionKindAllCasesContainsBoth() {
        let cases = MacOSPermissionKind.allCases
        XCTAssertTrue(cases.contains(.accessibility))
        XCTAssertTrue(cases.contains(.inputMonitoring))
    }

    func testMacOSPermissionKindIsRequiredOnCurrentOSAccessibilityIsAlwaysTrue() {
        XCTAssertTrue(MacOSPermissionKind.accessibility.isRequiredOnCurrentOS)
    }

    func testIsGrantedInStatusAccessibility() {
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertTrue(MacOSPermissionKind.accessibility.isGranted(in: status))
    }

    func testIsGrantedInStatusInputMonitoring() {
        let status = MacOSPermissionStatus(
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        XCTAssertTrue(MacOSPermissionKind.inputMonitoring.isGranted(in: status))
    }

    func testIsGrantedInStatusInputMonitoringNotGranted() {
        let status = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        XCTAssertFalse(MacOSPermissionKind.inputMonitoring.isGranted(in: status))
    }

    // MARK: - availableCases filtering

    func testAvailableCasesOnPreTahoeIncludesBothPermissions() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let cases = MacOSPermissionKind.availableCases
        XCTAssertTrue(cases.contains(.accessibility))
        XCTAssertTrue(cases.contains(.inputMonitoring))
    }

    func testAvailableCasesOnTahoeExcludesInputMonitoring() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        let cases = MacOSPermissionKind.availableCases
        XCTAssertTrue(cases.contains(.accessibility))
        XCTAssertFalse(cases.contains(.inputMonitoring))
        XCTAssertEqual(cases.count, 1)
    }

    func testAvailableCasesOnTahoeHasInputMonitoringNotRequired() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(false)
        XCTAssertFalse(MacOSPermissionKind.inputMonitoring.isRequiredOnCurrentOS)
    }

    func testAvailableCasesOnPreTahoeHasInputMonitoringRequired() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        XCTAssertTrue(MacOSPermissionKind.inputMonitoring.isRequiredOnCurrentOS)
    }

    // MARK: - Injected closures (closure seam)

    func testCurrentStatusUsesInjectedClosures() {
        let status = MacOSPermissionCheck.currentStatus(
            isAccessibilityTrusted: { true },
            isInputMonitoringGranted: { false }
        )
        XCTAssertTrue(status.accessibilityGranted)
        XCTAssertFalse(status.inputMonitoringGranted)
        // Without override, behavior depends on the host macOS version.
        // We just verify the closures were honored.
    }

    func testCurrentStatusBothInjectedClosuresGrantingReturnsSatisfiedOnPreTahoe() {
        MacOSPermissionStatus._setInputMonitoringRequiredOverrideForTests(true)
        let status = MacOSPermissionCheck.currentStatus(
            isAccessibilityTrusted: { true },
            isInputMonitoringGranted: { true }
        )
        XCTAssertTrue(status.isSatisfied)
    }

    // MARK: - Equatable

    func testMacOSPermissionStatusEquatable() {
        let a = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let b = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let c = MacOSPermissionStatus(
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
