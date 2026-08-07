import Foundation

public struct PersistedSpaces: Codable {
    public var records: [Int: SpaceLabelRecord]
    public var labels: [Int: SpaceLabel] { records.mapValues(\.label) }          // legacy mirror + convenience
    public var spaceDisplayByID: [Int: String] { records.compactMapValues(\.display) }

    enum CodingKeys: String, CodingKey { case records, labels, spaceDisplayByID }

    public init(records: [Int: SpaceLabelRecord] = [:]) {
        self.records = records
    }

    /// Convenience for tests / callers; derives records (display association optional).
    public init(labels: [Int: SpaceLabel] = [:], spaceDisplayByID: [Int: String] = [:]) {
        self.records = Dictionary(uniqueKeysWithValues: labels.map {
            ($0.key, SpaceLabelRecord(label: $0.value, display: spaceDisplayByID[$0.key]))
        })
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let records = try c.decodeIfPresent([Int: SpaceLabelRecord].self, forKey: .records) {
            self.records = records
        } else {
            // Backward compat: pre-fix files have `labels` (released) and possibly
            // `spaceDisplayByID` (uncommitted worktree builds).
            let labels = try c.decodeIfPresent([Int: SpaceLabel].self, forKey: .labels) ?? [:]
            let displays = try c.decodeIfPresent([Int: String].self, forKey: .spaceDisplayByID) ?? [:]
            self.records = Dictionary(uniqueKeysWithValues: labels.map {
                ($0.key, SpaceLabelRecord(label: $0.value, display: displays[$0.key]))
            })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(records, forKey: .records)      // authoritative
        try c.encode(labels, forKey: .labels)        // mirror so older builds can still read the file
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

    public init(fileURL: URL) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
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
        do {
            return try decoder.decode(PersistedSpaces.self, from: data)
        } catch {
            quarantineCorruptedData(data)
            return PersistedSpaces()
        }
    }

    /// Never silently overwrite a corrupt spaces.json: preserve the raw payload so no
    /// data is lost; the app still recovers with an empty store.
    private func quarantineCorruptedData(_ data: Data) {
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".corrupt")
        try? data.write(to: backupURL, options: .atomic)
    }

    public func save(_ persisted: PersistedSpaces) throws {
        let data = try encoder.encode(persisted)
        try data.write(to: fileURL, options: .atomic)
    }
}
