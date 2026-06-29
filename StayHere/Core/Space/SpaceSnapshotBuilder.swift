import Foundation

/// Builds JSON snapshots of the current space state with cached formatters.
public struct SpaceSnapshotBuilder {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public init() {}

    /// Returns a JSON string representing the current space state.
    /// Returns `"{}"` on encoding failure.
    public func json(
        spaces: [SpaceIdentity],
        labels: [Int: SpaceLabel],
        activeSpaceID: Int?,
        displayOrder: [Int]
    ) -> String {
        let snap = SpaceStateSnapshot(
            timestampISO8601: Self.isoFormatter.string(from: Date()),
            activeSpaceID: activeSpaceID,
            spaces: spaces,
            labels: labels,
            displayOrder: displayOrder
        )
        guard let data = try? encoder.encode(snap),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
