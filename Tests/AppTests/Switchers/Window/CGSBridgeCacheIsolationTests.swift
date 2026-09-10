import XCTest
@testable import Core

final class CGSBridgeCacheIsolationTests: XCTestCase {

    // MARK: - Recording cache for tests

    private final class RecordingSpacesCache: SpacesForWindowCaching {
        var resolvedCalls: [Int] = []
        var storeCalls: [(windowID: Int, spaces: [Int])] = []
        var clearCalled = false
        var cachedHit: [Int]?

        func resolved(windowID: Int) -> [Int]? {
            resolvedCalls.append(windowID)
            return cachedHit
        }

        func store(windowID: Int, spaces: [Int]) {
            storeCalls.append((windowID, spaces))
        }

        func clear() {
            clearCalled = true
        }
    }

    // MARK: - Tests

    func testInjectedCacheIsUsedBySpacesForWindow() {
        let cache = RecordingSpacesCache()
        cache.cachedHit = [42]
        let bridge = CGSBridge(spacesCache: cache)

        _ = bridge.spacesForWindow(windowID: 123)

        XCTAssertEqual(cache.resolvedCalls, [123], "cache should be queried for the window ID")
        XCTAssertTrue(cache.storeCalls.isEmpty, "store must not be called when cache hits")
    }

    func testClearSpacesCacheClearsOnlyThatInstance() {
        let cacheA = RecordingSpacesCache()
        let cacheB = RecordingSpacesCache()
        let bridgeA = CGSBridge(spacesCache: cacheA)
        _ = CGSBridge(spacesCache: cacheB)

        bridgeA.clearSpacesCache()

        XCTAssertTrue(cacheA.clearCalled, "bridge A's cache must be cleared")
        XCTAssertFalse(cacheB.clearCalled, "bridge B's cache must NOT be affected")
    }

    func testDefaultInitAndLiveCompile() {
        let adHoc = CGSBridge()
        let live = CGSBridge.live

        // Both compile and clearSpacesCache runs without error
        adHoc.clearSpacesCache()
        live.clearSpacesCache()
    }

    // MARK: - Resolver injection tests

    private final class RecordingSymbolResolver: CGSSymbolResolving {
        var ensureHandleCalled = false
        var resolveCalls: [String] = []
        var isResolvedCalls: [String] = []

        func ensureHandle() -> UnsafeMutableRawPointer? {
            ensureHandleCalled = true
            return nil
        }

        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            resolveCalls.append(name)
            return nil
        }

        func isResolved<T>(_ name: String, as type: T.Type) -> Bool {
            isResolvedCalls.append(name)
            return false
        }
    }

    func testInjectedResolverIsUsedByActiveSpaceID() {
        let resolver = RecordingSymbolResolver()
        let bridge = CGSBridge(symbolResolver: resolver)

        _ = bridge.activeSpaceID()

        // mainConn is the first accessor; when it returns nil, activeSpaceID() bails early
        XCTAssertTrue(resolver.resolveCalls.contains("_CGSDefaultConnection"))
    }

    func testInjectedResolverIsUsedByManagedSnapshot() {
        let resolver = RecordingSymbolResolver()
        let bridge = CGSBridge(symbolResolver: resolver)

        _ = bridge.managedSnapshot()

        // mainConn is the first accessor; when it returns nil, managedSnapshot() bails early
        XCTAssertTrue(resolver.resolveCalls.contains("_CGSDefaultConnection"))
    }

    func testTwoBridgesHaveIndependentResolvers() {
        let resolverA = RecordingSymbolResolver()
        let resolverB = RecordingSymbolResolver()
        let bridgeA = CGSBridge(symbolResolver: resolverA)
        _ = CGSBridge(symbolResolver: resolverB)

        _ = bridgeA.activeSpaceID()

        XCTAssertTrue(resolverA.resolveCalls.contains("_CGSDefaultConnection"), "resolver A should be called")
        XCTAssertTrue(resolverB.resolveCalls.isEmpty, "resolver B should NOT be called by bridge A")
    }
}
