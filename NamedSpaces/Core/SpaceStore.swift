import Foundation

public struct PersistedSpaces: Codable {
    public var labels: [Int: SpaceLabel]
    public var displayOrder: [Int]

    enum CodingKeys: String, CodingKey {
        case labels
        case displayOrder
    }

    public init(labels: [Int: SpaceLabel] = [:], displayOrder: [Int] = []) {
        self.labels = labels
        self.displayOrder = displayOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.labels = try c.decodeIfPresent([Int: SpaceLabel].self, forKey: .labels) ?? [:]
        self.displayOrder = try c.decodeIfPresent([Int].self, forKey: .displayOrder) ?? []
    }
}

public final class SpaceStore {
    public let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NamedSpaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("spaces.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
