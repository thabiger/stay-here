import AppKit
import XCTest
@testable import StayHereApp

private struct FakeIconApplication: WindowListApplication {
    let isHidden: Bool
    let localizedName: String?
    let bundleURL: URL?
}

final class WindowIconProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WindowIconProvider.iconCache.removeAllObjects()
    }

    override func tearDown() {
        WindowIconProvider.iconCache.removeAllObjects()
        super.tearDown()
    }

    // MARK: - Cache hit returns same instance

    func testCacheHitReturnsSameInstance() {
        let provider = WindowIconProvider()
        let app = FakeIconApplication(
            isHidden: false,
            localizedName: "Test",
            bundleURL: Bundle.main.bundleURL
        )
        let icon1 = provider.icon(for: app)
        let icon2 = provider.icon(for: app)
        XCTAssertTrue(icon1 === icon2, "cache hit must return the same NSImage instance")
    }

    // MARK: - Resized icon cached on miss and hit

    func testResizedIconCachedAndSized() {
        let provider = WindowIconProvider()
        let app = FakeIconApplication(
            isHidden: false,
            localizedName: "Test",
            bundleURL: Bundle.main.bundleURL
        )
        let icon1 = provider.icon(for: app)
        XCTAssertEqual(icon1.size.width, 18, "icon must be resized to 18x18")
        XCTAssertEqual(icon1.size.height, 18, "icon must be resized to 18x18")

        let rep = icon1.representations.first as? NSBitmapImageRep
        XCTAssertEqual(rep?.pixelsWide, 36, "icon must render at 2x for Retina crispness")

        let icon2 = provider.icon(for: app)
        XCTAssertTrue(icon1 === icon2, "cache hit must return the same instance (no re-resize)")
        XCTAssertEqual(icon2.size.width, 18)
        XCTAssertEqual(icon2.size.height, 18)
    }

    // MARK: - Distinct bundleURL.path keys are distinct cache entries

    func testDifferentBundleURLsAreDistinctCacheEntries() {
        let provider = WindowIconProvider()
        let appA = FakeIconApplication(
            isHidden: false,
            localizedName: "App A",
            bundleURL: URL(fileURLWithPath: "/Applications/AppA.app")
        )
        let appB = FakeIconApplication(
            isHidden: false,
            localizedName: "App B",
            bundleURL: URL(fileURLWithPath: "/Applications/AppB.app")
        )
        let iconA = provider.icon(for: appA)
        let iconB = provider.icon(for: appB)
        XCTAssertFalse(iconA === iconB, "distinct bundleURL paths must produce distinct cache entries")
    }

    // MARK: - Generic fallback cached under sentinel key

    func testGenericFallbackCached() {
        let provider = WindowIconProvider()
        let iconNilApp = provider.icon(for: nil)
        let appWithNilURL = FakeIconApplication(
            isHidden: false,
            localizedName: "No Bundle",
            bundleURL: nil
        )
        let iconNilURL = provider.icon(for: appWithNilURL)
        let iconNilAppAgain = provider.icon(for: nil)

        XCTAssertTrue(iconNilApp === iconNilURL, "nil app and nil bundleURL must share the generic fallback")
        XCTAssertTrue(iconNilApp === iconNilAppAgain, "repeated nil calls must return the same cached instance")
    }

    // MARK: - Concurrent access is thread-safe

    func testConcurrentAccessIsThreadSafe() {
        let provider = WindowIconProvider()
        let app = FakeIconApplication(
            isHidden: false,
            localizedName: "Test",
            bundleURL: Bundle.main.bundleURL
        )
        let lock = NSLock()
        var results: [NSImage] = []

        // Warm the cache first on a single thread to establish the canonical instance
        _ = provider.icon(for: app)
        let canonicalIcon = provider.icon(for: app)

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let icon = provider.icon(for: app)
            lock.lock()
            results.append(icon)
            lock.unlock()
        }

        XCTAssertEqual(results.count, 200, "all concurrent calls must complete")
        for result in results {
            XCTAssertTrue(
                result === canonicalIcon,
                "every concurrent call must return the same cached instance"
            )
            XCTAssertEqual(result.size.width, 18)
            XCTAssertEqual(result.size.height, 18)
        }
    }
}
