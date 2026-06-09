import Foundation

public struct UpdateInfo: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL
    public let downloadURL: URL
    public let title: String
    public let notes: String
    public let publishedAt: Date

    public init(
        version: String,
        releaseURL: URL,
        downloadURL: URL,
        title: String,
        notes: String,
        publishedAt: Date
    ) {
        self.version = version
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.title = title
        self.notes = notes
        self.publishedAt = publishedAt
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case noUpdate
    case updateAvailable(UpdateInfo)
}

public protocol AppVersionProviding: Sendable {
    var shortVersionString: String { get }
    var buildNumber: String { get }
}

public struct AppVersionProvider: AppVersionProviding, Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public var shortVersionString: String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public var buildNumber: String {
        bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

public final class UpdateDefaultsStore: @unchecked Sendable {
    public static let standard = UpdateDefaultsStore(defaults: .standard)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func object(forKey defaultName: String) -> Any? {
        defaults.object(forKey: defaultName)
    }

    func string(forKey defaultName: String) -> String? {
        defaults.string(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        defaults.set(value, forKey: defaultName)
    }

    func removeObject(forKey defaultName: String) {
        defaults.removeObject(forKey: defaultName)
    }
}

public protocol UpdateService: AnyObject {
    func cachedUpdateInfo() async -> UpdateInfo?
    func checkForUpdates(force: Bool) async throws -> UpdateCheckResult
}

public enum UpdateCheckError: LocalizedError, Equatable, Sendable {
    case rateLimited
    case unexpectedStatusCode(Int, String?)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "GitHub rate limited update checks. Please try again later."
        case .unexpectedStatusCode(let statusCode, let message):
            if let message, !message.isEmpty {
                return "GitHub update check failed (\(statusCode)): \(message)"
            }
            return "GitHub update check failed with HTTP \(statusCode)."
        case .malformedResponse:
            return "GitHub returned an unexpected response while checking for updates."
        }
    }
}

public struct SemanticVersion: Equatable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(parsing rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let parts = normalized.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public actor GitHubReleaseUpdateService: UpdateService {
    private enum CacheKey {
        static let lastCheckAt = "updates.lastCheckAt"
        static let version = "updates.latest.version"
        static let releaseURL = "updates.latest.releaseURL"
        static let downloadURL = "updates.latest.downloadURL"
        static let title = "updates.latest.title"
        static let notes = "updates.latest.notes"
        static let publishedAt = "updates.latest.publishedAt"
    }

    private struct GitHubReleaseResponse: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let name: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case name
            case body
            case draft
            case prerelease
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct GitHubErrorResponse: Decodable {
        let message: String?
    }

    private let owner: String
    private let repository: String
    private let defaults: UpdateDefaultsStore
    private let versionProvider: any AppVersionProviding
    private let fetchData: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let currentDate: @Sendable () -> Date
    private let cacheValidity: TimeInterval
    private let decoder: JSONDecoder

    public init(
        owner: String = "thabiger",
        repository: String = "stay-here",
        defaults: UpdateDefaultsStore = .standard,
        versionProvider: any AppVersionProviding = AppVersionProvider(),
        fetchData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        },
        currentDate: @escaping @Sendable () -> Date = { Date() },
        cacheValidity: TimeInterval = 24 * 60 * 60
    ) {
        self.owner = owner
        self.repository = repository
        self.defaults = defaults
        self.versionProvider = versionProvider
        self.fetchData = fetchData
        self.currentDate = currentDate
        self.cacheValidity = cacheValidity
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func cachedUpdateInfo() -> UpdateInfo? {
        loadCachedUpdateInfo()
    }

    public func checkForUpdates(force: Bool) async throws -> UpdateCheckResult {
        if !force, shouldUseCachedResult() {
            return cachedResult()
        }

        let request = makeLatestReleaseRequest()
        let (data, response) = try await fetchData(request)
        try validate(response: response, data: data)

        let release = try decoder.decode(GitHubReleaseResponse.self, from: data)
        let updateInfo = updateInfo(from: release)
        storeCache(updateInfo: updateInfo, checkedAt: currentDate())
        return result(for: updateInfo)
    }

    private func shouldUseCachedResult() -> Bool {
        guard let lastCheckAt = defaults.object(forKey: CacheKey.lastCheckAt) as? Date else {
            return false
        }
        return currentDate().timeIntervalSince(lastCheckAt) < cacheValidity
    }

    private func cachedResult() -> UpdateCheckResult {
        result(for: loadCachedUpdateInfo())
    }

    private func result(for updateInfo: UpdateInfo?) -> UpdateCheckResult {
        guard let updateInfo,
              let latestVersion = SemanticVersion(parsing: updateInfo.version),
              let currentVersion = SemanticVersion(parsing: versionProvider.shortVersionString),
              latestVersion > currentVersion else {
            return .noUpdate
        }
        return .updateAvailable(updateInfo)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.malformedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try? decoder.decode(GitHubErrorResponse.self, from: data)
            let message = errorBody?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch httpResponse.statusCode {
            case 403:
                if let message, message.localizedCaseInsensitiveContains("rate limit") {
                    throw UpdateCheckError.rateLimited
                }
                throw UpdateCheckError.unexpectedStatusCode(httpResponse.statusCode, message)
            default:
                throw UpdateCheckError.unexpectedStatusCode(httpResponse.statusCode, message)
            }
        }
    }

    private func updateInfo(from release: GitHubReleaseResponse) -> UpdateInfo? {
        guard !release.draft, !release.prerelease,
              let version = normalizedVersion(release.tagName),
              SemanticVersion(parsing: version) != nil else {
            return nil
        }

        let downloadURL = preferredDownloadURL(from: release.assets) ?? release.htmlURL
        let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? release.name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "StayHere \(version)"
        return UpdateInfo(
            version: version,
            releaseURL: release.htmlURL,
            downloadURL: downloadURL,
            title: title,
            notes: release.body ?? "",
            publishedAt: release.publishedAt
        )
    }

    private func preferredDownloadURL(from assets: [GitHubReleaseResponse.Asset]) -> URL? {
        if let dmg = assets.first(where: { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }) {
            return dmg.browserDownloadURL
        }

        if let zip = assets.first(where: { asset in
            asset.name.lowercased().hasSuffix(".zip")
        }) {
            return zip.browserDownloadURL
        }

        return nil
    }

    private func normalizedVersion(_ rawValue: String) -> String? {
        guard let version = SemanticVersion(parsing: rawValue) else { return nil }
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    private func makeLatestReleaseRequest() -> URLRequest {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("StayHere/\(versionProvider.shortVersionString)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func loadCachedUpdateInfo() -> UpdateInfo? {
        guard let version = defaults.string(forKey: CacheKey.version),
              let releaseURLString = defaults.string(forKey: CacheKey.releaseURL),
              let releaseURL = URL(string: releaseURLString),
              let downloadURLString = defaults.string(forKey: CacheKey.downloadURL),
              let downloadURL = URL(string: downloadURLString),
              let title = defaults.string(forKey: CacheKey.title),
              let notes = defaults.string(forKey: CacheKey.notes),
              let publishedAt = defaults.object(forKey: CacheKey.publishedAt) as? Date else {
            return nil
        }

        return UpdateInfo(
            version: version,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            title: title,
            notes: notes,
            publishedAt: publishedAt
        )
    }

    private func storeCache(updateInfo: UpdateInfo?, checkedAt: Date) {
        defaults.set(checkedAt, forKey: CacheKey.lastCheckAt)

        guard let updateInfo else {
            defaults.removeObject(forKey: CacheKey.version)
            defaults.removeObject(forKey: CacheKey.releaseURL)
            defaults.removeObject(forKey: CacheKey.downloadURL)
            defaults.removeObject(forKey: CacheKey.title)
            defaults.removeObject(forKey: CacheKey.notes)
            defaults.removeObject(forKey: CacheKey.publishedAt)
            return
        }

        defaults.set(updateInfo.version, forKey: CacheKey.version)
        defaults.set(updateInfo.releaseURL.absoluteString, forKey: CacheKey.releaseURL)
        defaults.set(updateInfo.downloadURL.absoluteString, forKey: CacheKey.downloadURL)
        defaults.set(updateInfo.title, forKey: CacheKey.title)
        defaults.set(updateInfo.notes, forKey: CacheKey.notes)
        defaults.set(updateInfo.publishedAt, forKey: CacheKey.publishedAt)
    }
}
