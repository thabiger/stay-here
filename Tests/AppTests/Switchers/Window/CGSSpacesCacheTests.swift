import XCTest
@testable import Core

final class CGSSpacesCacheTests: XCTestCase {
    func testHitAndMiss() {
        let cache = CGSSpacesCache()

        // Miss for unknown window
        XCTAssertNil(cache.resolved(windowID: 999))

        // Store and hit within TTL
        cache.store(windowID: 1, spaces: [100, 200])
        XCTAssertEqual(cache.resolved(windowID: 1), [100, 200])
    }

    func testExpiresAfterTTL() {
        var now = Date()
        let cache = CGSSpacesCache(now: { now })

        cache.store(windowID: 1, spaces: [100])
        XCTAssertEqual(cache.resolved(windowID: 1), [100], "should hit within TTL")

        // Advance past TTL
        now += 3.1
        XCTAssertNil(cache.resolved(windowID: 1), "should expire after TTL")
    }

    func testConcurrentAccess() {
        let cache = CGSSpacesCache()
        let n = 100
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        for i in 0..<n {
            group.enter()
            queue.async {
                let windowID = i + 1
                cache.store(windowID: windowID, spaces: [windowID * 100])
                group.leave()
            }
        }
        group.wait()

        // Verify all values are correct
        for i in 0..<n {
            let windowID = i + 1
            XCTAssertEqual(cache.resolved(windowID: windowID), [windowID * 100])
        }
    }

    func testEmptyResultCached() {
        let cache = CGSSpacesCache()

        cache.store(windowID: 1, spaces: [])
        XCTAssertEqual(cache.resolved(windowID: 1), [], "empty result should be cached within TTL")
    }

    func testClearRemovesAllEntries() {
        let cache = CGSSpacesCache()

        cache.store(windowID: 1, spaces: [100])
        cache.store(windowID: 2, spaces: [200])
        XCTAssertEqual(cache.resolved(windowID: 1), [100])
        XCTAssertEqual(cache.resolved(windowID: 2), [200])

        cache.clear()

        XCTAssertNil(cache.resolved(windowID: 1), "clear must remove all entries")
        XCTAssertNil(cache.resolved(windowID: 2), "clear must remove all entries")
    }
}
