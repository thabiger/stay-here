import XCTest
import Core
@testable import Activation

final class ActivationExecutorCancellationTests: XCTestCase {
    private func makeContext() -> ActivationContext {
        ActivationContext(
            bundleID: "com.example.App",
            activeSpaceIDs: [1],
            targetSpaceID: 1,
            appWindowSummary: nil,
            singleWindowSpaceID: 100,
            optionHeld: true
        )
    }

    // MARK: - Control: polling happens

    /// Sanity check: `waitForActiveSpace` actually polls `currentSpaceID`.
    /// Without this, the cancellation test would pass trivially.
    /// Note: `currentSpaceID() == nil` is treated as unknown (keeps
    /// polling). Only a confirmed match or timeout terminates the chain.
    func testPollingContinuesWithoutCancellation() {
        var currentSpaceIDCalls = 0
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: {
                currentSpaceIDCalls += 1
                return 999  // non-nil, never matches spaceID 1
            }
        )

        executor.waitForActiveSpace(1, timeout: 5.0) { }

        let exp1 = expectation(description: "first batch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)
        let count1 = currentSpaceIDCalls

        let exp2 = expectation(description: "second batch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        let count2 = currentSpaceIDCalls

        XCTAssertGreaterThan(count1, 1, "polling should call currentSpaceID multiple times")
        XCTAssertGreaterThan(count2, count1, "polling should continue without cancellation")
    }

    /// On timeout the `then` callback fires as a degraded fallback so the
    /// app is still activated (primary goal), but the timeout seam records
    /// that the space switch did not complete within the deadline.
    func testWaitForActiveSpaceFiresThenAsFallbackOnTimeout() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }  // never matches → timeout
        )

        executor.waitForActiveSpace(1, timeout: 0.2) { }

        // Wait for the 0.2s timeout + buffer.
        let exp = expectation(description: "timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 1, "then fires as degraded fallback on timeout")
        XCTAssertEqual(executor.testTimeoutCallCount, 1, "timeout branch must execute once")
    }

    /// Success path: when `currentSpaceID()` eventually matches the
    /// target space, `then` fires exactly once and no timeout is recorded.
    func testWaitForActiveSpaceThenIsCalledWhenSpaceMatches() {
        var calls = 0
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: {
                calls += 1
                return calls >= 3 ? 1 : 999   // matches spaceID 1 on 3rd poll
            }
        )

        executor.waitForActiveSpace(1, timeout: 5.0) { }

        let exp = expectation(description: "success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 1, "then fires once when space matches")
        XCTAssertEqual(executor.testTimeoutCallCount, 0, "no timeout on success")
    }

    /// nil from `currentSpaceID()` is treated as unknown (space detection
    /// failed) — it must NOT fire `then()` prematurely. The poll chain
    /// keeps going until the timeout elapses, at which point `then` fires
    /// as a degraded fallback.
    func testNilSpaceIDDoesNotFireThenPrematurely() {
        var calls = 0
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: {
                calls += 1
                return nil  // always nil — detection broken
            }
        )

        executor.waitForActiveSpace(1, timeout: 0.2) { }

        // Check at 0.15s — well before 0.2s timeout, then must NOT have fired.
        let exp1 = expectation(description: "mid-poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 0, "then must NOT fire while nil is returned")
        XCTAssertGreaterThan(calls, 1, "polling must continue when nil is returned")

        // Wait for timeout to elapse — then fires as degraded fallback.
        let exp2 = expectation(description: "after timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 1, "then fires as degraded fallback after timeout")
        XCTAssertEqual(executor.testTimeoutCallCount, 1, "timeout branch must execute once")
    }

    // MARK: - Direct cancellation: cancelAllPendingWork

    /// R2/C13: after `cancelAllPendingWork`, the polling chain must
    /// stop invoking `currentSpaceID` even though `currentSpaceID` would
    /// otherwise keep returning a non-matching value and the chain
    /// would keep polling until its 5-second timeout.
    func testPollingStopsAfterCancelAllPendingWork() {
        var currentSpaceIDCalls = 0
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: {
                currentSpaceIDCalls += 1
                return 999
            }
        )

        executor.waitForActiveSpace(1, timeout: 5.0) { }

        // Let several poll iterations fire (50 ms each).
        let exp1 = expectation(description: "polls")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)
        let countAfterStart = currentSpaceIDCalls
        XCTAssertGreaterThan(countAfterStart, 1, "polling should be active before cancel")

        executor.cancelAllPendingWork()

        // Wait long enough for at least 3 more poll iterations to fire
        // if cancellation were broken.
        let exp2 = expectation(description: "after cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        let countAfterCancel = currentSpaceIDCalls

        XCTAssertEqual(
            countAfterCancel, countAfterStart,
            "no more polls after cancellation"
        )
    }

    /// R2/C13: after `cancelAllPendingWork`, the `then` callback must
    /// NOT fire — even when the chain is mid-poll and would otherwise
    /// have run until its 5-second timeout.
    func testCancelAllPendingWorkPreventsThenFromFiring() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }  // would never match → 5s polling
        )

        executor.waitForActiveSpace(1, timeout: 5.0) { }

        // Cancel quickly, well before the 5 s timeout.
        let exp1 = expectation(description: "before cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)
        executor.cancelAllPendingWork()
        XCTAssertEqual(executor.testThenCallCount, 0)

        // Wait long enough that the chain would have polled many more
        // times if cancellation didn't work.
        let exp2 = expectation(description: "after cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertEqual(
            executor.testThenCallCount, 0,
            "then must NOT fire after cancellation"
        )
    }

    /// `cancelAllPendingWork` is idempotent — calling it twice (or on
    /// an executor with no pending work) must be safe.
    func testCancelAllPendingWorkIsIdempotent() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }
        )

        executor.cancelAllPendingWork()  // no-op, no panic
        executor.cancelAllPendingWork()  // no-op again

        let exp = expectation(description: "after idempotent cancels")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(executor.testThenCallCount, 0)
    }

    // MARK: - Integration: switchToAppSpace cancels previous chain

    /// R2/C13/M4: rapid Option+clicks on the Dock must cancel the
    /// previous chain's `then` callback. Otherwise the old chain
    /// finishes its 1-second poll loop and calls `focus` redundantly
    /// after the user has already moved on.
    func testRapidSwitchToAppSpaceCancelsFirstChainsThen() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }  // never matches spaceID 100 → 1s polling
        )
        let context = makeContext()

        // Chain 1: starts a 1 s polling chain.
        _ = executor.execute(decision: .switchToSingleWindowSpace, context: context)

        // Wait briefly, then start chain 2 on the same executor.
        let exp1 = expectation(description: "first chain active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertEqual(executor.testThenCallCount, 0, "no then yet — chain still polling")

        _ = executor.execute(decision: .switchToSingleWindowSpace, context: context)

        // Chain 1 was cancelled (its then will never fire). Chain 2 times
        // out after ~1 s and fires then as a degraded fallback.
        let exp2 = expectation(description: "chain 2 timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2.0)

        XCTAssertEqual(
            executor.testThenCallCount, 1,
            "chain 1 cancelled, chain 2 fires then as degraded fallback on timeout"
        )
        XCTAssertEqual(
            executor.testTimeoutCallCount, 1,
            "only chain 2's timeout branch fires"
        )
    }

    /// A switch that completes around the deadline must be recorded as
    /// success (either the top-of-poll match or the final verification
    /// read observes the target space), never as a timeout.
    func testSwitchCompletingAroundDeadlineCountsAsSuccess() {
        var calls = 0
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: {
                calls += 1
                // First call returns 999 (no match), all subsequent calls return 1 (match).
                return calls == 1 ? 999 : 1
            }
        )

        executor.waitForActiveSpace(1, timeout: 0.2) { }

        let exp = expectation(description: "success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 1, "then fires once when space matches")
        XCTAssertEqual(executor.testTimeoutCallCount, 0, "no timeout — switch completed around deadline counts as success")
    }

    /// Cancellation arriving mid-timeout-branch (after the top-of-poll guard
    /// but before then() in the timeout fallback path) must NOT fire then()
    /// and must not increment any counter. This tests the re-check guards
    /// that close the TOCTOU window between the initial cancellation check
    /// and every then() call.
    func testCancellationMidTimeoutBranchPreventsThenAndCounters() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }  // never matches → timeout path
        )

        executor.waitForActiveSpace(1, timeout: 0.15) { }

        // Cancel at ~0.12s — after some polls have run but before the
        // 0.15s deadline elapses. The next poll tick (at ~0.15s+) would
        // enter the timeout branch; the re-check guard must catch the
        // cancellation and prevent then() + counter increments.
        let exp1 = expectation(description: "cancel window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            executor.cancelAllPendingWork()
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)

        // Wait for any pending poll to complete.
        let exp2 = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 0, "then must NOT fire when cancelled mid-timeout-branch")
        XCTAssertEqual(executor.testTimeoutCallCount, 0, "timeout counter must NOT increment when cancelled mid-timeout-branch")
    }
}
