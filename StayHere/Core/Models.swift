import Foundation

public struct SpaceIdentity: Codable, Hashable {
    public let id: Int
    public let display: String

    public init(id: Int, display: String) {
        self.id = id
        self.display = display
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
