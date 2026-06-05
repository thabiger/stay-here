import Foundation

public struct PersistedSpaces: Codable {
    public var labels: [Int: SpaceLabel]
    public var displayOrder: [Int]
    public var usesCustomDisplayOrder: Bool

    enum CodingKeys: String, CodingKey {
        case labels
        case displayOrder
        case usesCustomDisplayOrder
    }

    public init(
        labels: [Int: SpaceLabel] = [:],
        displayOrder: [Int] = [],
        usesCustomDisplayOrder: Bool = false
    ) {
        self.labels = labels
        self.displayOrder = displayOrder
        self.usesCustomDisplayOrder = usesCustomDisplayOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.labels = try c.decodeIfPresent([Int: SpaceLabel].self, forKey: .labels) ?? [:]
        self.displayOrder = try c.decodeIfPresent([Int].self, forKey: .displayOrder) ?? []
        self.usesCustomDisplayOrder = try c.decodeIfPresent(Bool.self, forKey: .usesCustomDisplayOrder) ?? false
    }
}

public final class SpaceStore {
    public let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support/StayHere", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("spaces.json")
        migrateLegacyStoreIfNeeded(
            from: home.appendingPathComponent("Library/Application Support/NamedSpaces/spaces.json"),
            to: fileURL
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    private func migrateLegacyStoreIfNeeded(from legacyURL: URL, to currentURL: URL) {
        guard !FileManager.default.fileExists(atPath: currentURL.path),
              FileManager.default.fileExists(atPath: legacyURL.path)
        else {
            return
        }

        try? FileManager.default.copyItem(at: legacyURL, to: currentURL)
    }

    public func load() -> PersistedSpaces {
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedSpaces() }
        return (try? decoder.decode(PersistedSpaces.self, from: data)) ?? PersistedSpaces()
    }

    public func save(_ persisted: PersistedSpaces) throws {
        let data = try encoder.encode(persisted)
        try data.write(to: fileURL, options: .atomic)
    }
}
