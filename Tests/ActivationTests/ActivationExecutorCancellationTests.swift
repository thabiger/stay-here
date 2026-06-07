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
    /// Note: `currentSpaceID() == nil` is the SUCCESS condition in the
    /// original code, so we return a non-nil value that never matches the
    /// target to make the chain keep polling.
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

    /// Sanity check: `then` is called after the timeout elapses.
    /// Without this, the cancellation integration test below would be
    /// ambiguous (we wouldn't know if 0 means "cancelled" or "not yet
    /// timed out").
    func testWaitForActiveSpaceThenIsCalledAfterTimeout() {
        let executor = ActivationExecutor(
            showSingleWindowHint: { _ in },
            switchToSpace: { _ in },
            currentSpaceID: { 999 }  // never matches → 0.2s polling
        )

        executor.waitForActiveSpace(1, timeout: 0.2) { }

        // Wait for the 0.2s timeout + buffer.
        let exp = expectation(description: "timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(executor.testThenCallCount, 1, "then should be called after timeout")
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

        // Chain 1 was cancelled (its then will never fire). Chain 2
        // will time out after ~1 s and call then once. Wait long enough
        // for chain 2 to complete.
        let exp2 = expectation(description: "chain 2 timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2.0)

        XCTAssertEqual(
            executor.testThenCallCount, 1,
            "only chain 2's then should fire — chain 1 was cancelled"
        )
    }
}
