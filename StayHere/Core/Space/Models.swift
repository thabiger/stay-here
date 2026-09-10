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

/// Single source of truth for a persisted space label: the label, the display the
/// space was last positively observed on, and (in-memory only) the absence-evidence
/// budget used by `SpaceLabelStore`. Persisted form carries only `label` + `display`.
public struct SpaceLabelRecord: Codable, Hashable {
    public var label: SpaceLabel
    public var display: String?
    public var absenceCount: Int = 0
    public var firstAbsenceAt: Date?

    enum CodingKeys: String, CodingKey { case label, display }

    public init(
        label: SpaceLabel,
        display: String? = nil,
        absenceCount: Int = 0,
        firstAbsenceAt: Date? = nil
    ) {
        self.label = label
        self.display = display
        self.absenceCount = absenceCount
        self.firstAbsenceAt = firstAbsenceAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(SpaceLabel.self, forKey: .label)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        absenceCount = 0
        firstAbsenceAt = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(display, forKey: .display)
    }
}

public struct SpaceStateSnapshot: Codable {
    public var timestampISO8601: String
    public var activeSpaceID: Int?
    public var spaces: [SpaceIdentity]
    public var labels: [Int: SpaceLabel]
}
