import XCTest
import Foundation
import Core

final class UpdateServiceTests: XCTestCase {
    func testSemanticVersionComparisonHandlesNumericOrdering() {
        let older = try? XCTUnwrap(SemanticVersion(parsing: "0.1.9"))
        let newer = try? XCTUnwrap(SemanticVersion(parsing: "0.1.10"))
        XCTAssertNotNil(older)
        XCTAssertNotNil(newer)
        XCTAssertLessThan(older!, newer!)
        XCTAssertEqual(SemanticVersion(parsing: "v1.2.3"), SemanticVersion(parsing: "1.2.3"))
    }

    func testSemanticVersionRejectsMalformedAndPartialVersions() {
        XCTAssertNil(SemanticVersion(parsing: "1.2"))
        XCTAssertNil(SemanticVersion(parsing: "banana"))
    }

    func testCheckForUpdatesReturnsAvailableUpdateAndPrefersDMG() async throws {
        let defaults = makeDefaults()
        let service = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                (
                    Self.releaseJSON(
                        tag: "v0.1.2",
                        assets: [
                            ("StayHere.zip", "https://example.com/StayHere.zip"),
                            ("StayHere.dmg", "https://example.com/StayHere.dmg")
                        ]
                    ),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let result = try await service.checkForUpdates(force: true)

        guard case .updateAvailable(let info) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(info.version, "0.1.2")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/StayHere.dmg")
    }

    func testCheckForUpdatesIgnoresPrereleasesAndMalformedTags() async throws {
        let defaults = makeDefaults()
        let prereleaseService = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                (
                    Self.releaseJSON(tag: "v0.2.0", prerelease: true),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let malformedTagService = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                (
                    Self.releaseJSON(tag: "latest"),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let prereleaseResult = try await prereleaseService.checkForUpdates(force: true)
        let malformedTagResult = try await malformedTagService.checkForUpdates(force: true)

        XCTAssertEqual(prereleaseResult, .noUpdate)
        XCTAssertEqual(malformedTagResult, .noUpdate)
    }

    func testCheckForUpdatesThrowsGenericGitHubErrorFor404() async {
        let defaults = makeDefaults()
        let service = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                (
                    Data(#"{"message":"Not Found"}"#.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        do {
            _ = try await service.checkForUpdates(force: true)
            XCTFail("Expected a 404 update error")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .unexpectedStatusCode(404, "Not Found"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCachedAutomaticCheckSkipsNetworkAndReturnsCachedUpdate() async throws {
        let defaults = makeDefaults()
        let fetchCounter = FetchCounter()
        let now = Date()
        let service = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                await fetchCounter.increment()
                return (
                    Self.releaseJSON(tag: "v0.1.2"),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            currentDate: { now }
        )

        _ = try await service.checkForUpdates(force: true)
        let result = try await service.checkForUpdates(force: false)
        let fetchCount = await fetchCounter.value

        XCTAssertEqual(fetchCount, 1)
        guard case .updateAvailable(let info) = result else {
            return XCTFail("Expected cached update")
        }
        XCTAssertEqual(info.version, "0.1.2")
    }

    func testManualCheckBypassesFreshCache() async throws {
        let defaults = makeDefaults()
        let fetchCounter = FetchCounter()
        let now = Date()
        let service = GitHubReleaseUpdateService(
            defaults: defaults,
            versionProvider: StubVersionProvider(shortVersionString: "0.1.0"),
            fetchData: { _ in
                await fetchCounter.increment()
                return (
                    Self.releaseJSON(tag: "v0.1.2"),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            },
            currentDate: { now }
        )

        _ = try await service.checkForUpdates(force: true)
        _ = try await service.checkForUpdates(force: true)
        let fetchCount = await fetchCounter.value

        XCTAssertEqual(fetchCount, 2)
    }

    private func makeDefaults() -> UpdateDefaultsStore {
        let suiteName = "UpdateServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UpdateDefaultsStore(defaults: defaults)
    }

    private static func releaseJSON(
        tag: String,
        prerelease: Bool = false,
        assets: [(String, String)] = []
    ) -> Data {
        let assetJSON = assets.map { name, url in
            """
            {"name":"\(name)","browser_download_url":"\(url)"}
            """
        }.joined(separator: ",")

        let json = """
        {
          "tag_name": "\(tag)",
          "html_url": "https://github.com/thabiger/stay-here/releases/tag/\(tag)",
          "name": "StayHere \(tag)",
          "body": "Bug fixes and polish.",
          "draft": false,
          "prerelease": \(prerelease ? "true" : "false"),
          "published_at": "2026-06-08T12:00:00Z",
          "assets": [\(assetJSON)]
        }
        """
        return Data(json.utf8)
    }
}

private struct StubVersionProvider: AppVersionProviding {
    let shortVersionString: String
    let buildNumber: String = "1"
}

private actor FetchCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
