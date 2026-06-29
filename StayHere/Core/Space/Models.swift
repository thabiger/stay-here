import Foundation

public enum SpaceKind: String, Codable, Hashable {
    case desktop
    case fullscreen
    case unknown
}

public struct SpaceIdentity: Codable, Hashable {
    public let id: Int
    public let display: String
    public let kind: SpaceKind
    public let systemName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case display
        case kind
        case systemName
    }

    public init(id: Int, display: String, kind: SpaceKind = .desktop, systemName: String? = nil) {
        self.id = id
        self.display = display
        self.kind = kind
        self.systemName = systemName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        display = try container.decode(String.self, forKey: .display)
        kind = try container.decodeIfPresent(SpaceKind.self, forKey: .kind) ?? .desktop
        systemName = try container.decodeIfPresent(String.self, forKey: .systemName)
    }
}

public struct SpaceLabel: Codable, Hashable {
    public var name: String
    public var emoji: String?
    public var colorHex: String?

    public init(name: String, emoji: String? = nil, colorHex: String? = nil) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
    }
}

public struct SpaceStateSnapshot: Codable {
    public var timestampISO8601: String
    public var activeSpaceID: Int?
    public var spaces: [SpaceIdentity]
    public var labels: [Int: SpaceLabel]
    public var displayOrder: [Int]
}
