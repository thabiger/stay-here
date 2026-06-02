import XCTest
import Core
@testable import Activation

final class ActivationPolicyTests: XCTestCase {
    func testLaunchWhenAppIsNotRunning() {
        let policy = ActivationPolicy(isAppRunning: { _ in false })
        let decision = policy.decide(makeContext(bundleID: "com.example.MissingApp"))

        XCTAssertEqual(decision, .launch)
    }

    func testSingleWindowAppShowsHint() {
        let policy = ActivationPolicy(isAppRunning: { _ in true })
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 1, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: false
            )
        )

        XCTAssertEqual(decision, .singleWindowHint)
    }

    func testSingleWindowAppStillShowsHintWithOption() {
        let policy = ActivationPolicy(isAppRunning: { _ in true })
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 1, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: true
            )
        )

        XCTAssertEqual(decision, .switchToSingleWindowSpace)
    }

    func testWindowOnTargetSpaceFocusesCurrentSpace() {
        let policy = ActivationPolicy(isAppRunning: { _ in true })
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 2, currentSpaceWindows: 0, targetSpaceWindows: 1),
                optionHeld: false
            )
        )

        XCTAssertEqual(decision, .focusCurrentSpace)
    }

    func testMultiWindowAppWithoutTargetSpaceCreatesNewWindow() {
        let policy = ActivationPolicy(isAppRunning: { _ in true })
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 2, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: false
            )
        )

        XCTAssertEqual(decision, .createNewWindow)
    }

    func testConfiguredSingleWindowAppShowsHintEvenWithMultipleWindows() {
        let policy = ActivationPolicy(
            isSingleWindowApp: { $0 == "com.example.App" },
            isAppRunning: { _ in true }
        )
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 3, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: false
            )
        )

        XCTAssertEqual(decision, .singleWindowHint)
    }

    func testConfiguredSingleWindowAppSwitchesWithOptionEvenWithMultipleWindows() {
        let policy = ActivationPolicy(
            isSingleWindowApp: { $0 == "com.example.App" },
            isAppRunning: { _ in true }
        )
        let decision = policy.decide(
            makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 3, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: true
            )
        )

        XCTAssertEqual(decision, .switchToSingleWindowSpace)
    }

    func testSingleWindowAppListParsesOneBundleIDPerLine() {
        let suiteName = "ActivationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = ActivationSettings(defaults: defaults)
        settings.singleWindowAppBundleIDs = [
            "com.apple.Notes",
            "  com.openai.codex  ",
            "",
            "com.apple.Notes"
        ]

        XCTAssertEqual(settings.singleWindowAppBundleIDs, ["com.apple.Notes", "com.openai.codex"])
    }

    func testSingleWindowOptionClickFallsThroughWhenSpaceCannotBeResolved() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in XCTFail("should not show the hint when the click should fall through") },
            switchToSpace: { _ in XCTFail("should not switch spaces when no destination can be resolved") }
        )

        let handled = executor.execute(
            decision: .switchToSingleWindowSpace,
            context: makeContext(
                bundleID: "com.example.App",
                summary: nil,
                singleWindowSpaceID: nil,
                optionHeld: true
            )
        )

        XCTAssertFalse(handled)
    }

    func testSingleWindowOptionClickSwitchesWhenSpaceIsKnown() {
        var switchedToSpaceID: Int?
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in XCTFail("should switch instead of showing the hint") },
            switchToSpace: { switchedToSpaceID = $0 }
        )

        let handled = executor.execute(
            decision: .switchToSingleWindowSpace,
            context: makeContext(
                bundleID: "com.example.App",
                summary: makeSummary(totalWindows: 1, currentSpaceWindows: 0, targetSpaceWindows: 0),
                optionHeld: true
            )
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(switchedToSpaceID, 1)
    }

    private func makeContext(
        bundleID: String,
        summary: AppWindowSummary? = nil,
        singleWindowSpaceID: Int? = 1,
        optionHeld: Bool = false
    ) -> ActivationContext {
        ActivationContext(
            bundleID: bundleID,
            activeSpaceIDs: [1],
            targetSpaceID: 1,
            appWindowSummary: summary,
            singleWindowSpaceID: singleWindowSpaceID,
            optionHeld: optionHeld
        )
    }

    private func makeSummary(
        totalWindows: Int,
        currentSpaceWindows: Int,
        targetSpaceWindows: Int
    ) -> AppWindowSummary {
        let current = makeWindows(count: currentSpaceWindows, startingAt: 100)
        let target = makeWindows(count: targetSpaceWindows, startingAt: 200)
        let remaining = max(totalWindows - current.count - target.count, 0)
        let other = makeWindows(count: remaining, startingAt: 300)

        return AppWindowSummary(
            bundleID: "com.example.App",
            pid: 1234,
            windowsOnCurrentSpace: current,
            windowsOnTargetSpace: target,
            allWindows: current + target + other
        )
    }

    private func makeWindows(count: Int, startingAt baseID: Int) -> [IndexedWindow] {
        (0..<count).map { offset in
            IndexedWindow(
                windowID: baseID + offset,
                pid: 1234,
                bundleID: "com.example.App",
                isOnScreen: true,
                layer: 0,
                spaceIDs: [offset + 1]
            )
        }
    }
}
