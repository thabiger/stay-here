import Foundation

// MARK: - Renaming

@MainActor
public protocol SpaceRenaming {
    func rename(spaceID: Int, name: String)
}

// MARK: - Reordering

@MainActor
public protocol SpaceReordering {
    func moveDisplayOrder(fromOffsets: IndexSet, toOffset: Int)
}

// MARK: - Snapshot Building

@MainActor
public protocol SpaceSnapshotBuilding {
    func snapshotJSON() -> String
}

// MARK: - Snapshot Refresh

@MainActor
public protocol SpaceSnapshotRefreshable: AnyObject {
    var activeSpaceID: Int? { get }
    func applyManagedSnapshot(_ snapshot: CGSBridge.ManagedSnapshot)
    func refreshSpaces()
}

// MARK: - Switch Snapshot

@MainActor
public protocol SpaceSwitchSnapshotProviding: AnyObject {
    var activeSpaceID: Int? { get }
    func currentSwitchSnapshot() -> SpaceSwitchSnapshot
    func orderedSpaceIDs() -> [Int]
}
