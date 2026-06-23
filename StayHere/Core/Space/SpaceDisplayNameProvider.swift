import Foundation

/// Encapsulates display name formatting for spaces, centralizing the
/// `"Unnamed space"` default-name constant.
public struct SpaceDisplayNameProvider {
    /// The default name used when a space has no custom label.
    public static let defaultUnnamedName = "Unnamed space"

    public init() {}

    /// Returns the custom label name for `spaceID`, or `defaultUnnamedName` if none exists.
    public func name(for spaceID: Int, labels: [Int: SpaceLabel]) -> String {
        labels[spaceID]?.name ?? Self.defaultUnnamedName
    }

    /// Returns the display name for `spaceID`.
    /// - If a custom name exists and is not `defaultUnnamedName`, returns it.
    /// - Otherwise falls back to `systemName` from the space identity, or `defaultUnnamedName`.
    public func displayName(
        for spaceID: Int,
        labels: [Int: SpaceLabel],
        spaces: [SpaceIdentity]
    ) -> String {
        let customName = name(for: spaceID, labels: labels)
        guard customName == Self.defaultUnnamedName else { return customName }
        let space = spaces.first(where: { $0.id == spaceID })
        return space?.systemName ?? customName
    }

    /// Returns the display name of the active space, or `defaultUnnamedName` if none is active.
    public func activeNameSummary(
        activeSpaceID: Int?,
        labels: [Int: SpaceLabel],
        spaces: [SpaceIdentity]
    ) -> String {
        guard let activeSpaceID else { return Self.defaultUnnamedName }
        return displayName(for: activeSpaceID, labels: labels, spaces: spaces)
    }

    /// Alias for `activeNameSummary` (kept for backward compatibility).
    public func activeName(
        activeSpaceID: Int?,
        labels: [Int: SpaceLabel],
        spaces: [SpaceIdentity]
    ) -> String {
        activeNameSummary(activeSpaceID: activeSpaceID, labels: labels, spaces: spaces)
    }
}
