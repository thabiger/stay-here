import AppKit

struct WindowEntry {
    let windowID: Int
    let pid: pid_t
    let appName: String
    let windowTitle: String?
    let icon: NSImage
}

struct WindowSpaceContext: Equatable {
    let spaceID: Int
    let desktopNumber: Int?
}

struct SpaceWindowGroup {
    let spaceID: Int
    let spaceLabel: String
    let entries: [WindowEntry]
}

struct WindowSwitcherItem: Identifiable {
    let id: Int
    let icon: NSImage
    let title: String
    let entry: WindowEntry
    let isSelected: Bool
}

struct WindowSwitcherSpaceGroup: Identifiable {
    let id: Int
    let spaceLabel: String
    let items: [WindowSwitcherItem]
}

struct WindowSwitcherSnapshot {
    let spaceGroups: [WindowSwitcherSpaceGroup]
    let title: String
    let subtitle: String
    let emptyMessage: String
    let iconName: String
    let showSpaceLabels: Bool
}

enum WindowSwitcherMode {
    case currentSpace
    case allSpaces
}

/// Whether a listing passed to the recency tracker covers all windows.
/// Complete listings (all spaces) are authoritative: IDs absent from them
/// are stale and pruned. Subset listings (current space) must preserve
/// recency for windows they do not contain.
enum WindowRecencyScope {
    case subset
    case complete
}

/// Pure recency-ordering contract — single source of truth for both the
/// listing path (WindowRecencyTracker.recentEntries) and the commit path
/// (WindowRecencyTracker.recordSelection).
///
/// Invariants:
/// 1. Recency-first: IDs in `recentIDs` that appear in `incomingIDs` keep
///    their existing recency order.
/// 2. Unknown IDs (in `incomingIDs` but not `recentIDs`) are appended in
///    incoming enumeration order.
/// 3. Scope: `.subset` preserves IDs absent from `incomingIDs` (appended in
///    prior recency order); `.complete` prunes them (authoritative listing).
/// 4. `promoting` IDs are forced to the front, in order, and deduplicated
///    against everything else (commit path: selected window + session start
///    window). Listing path passes `[]`.
/// 5. Subset-scope **listing** uses `mergeSubsetListing` (in-place; never
///    relocates other-space IDs). The `.subset` branch of `merge` is the
///    commit-path contract only (promotes to front, preserves tail).
enum RecencyOrdering {
    static func merge(
        recentIDs: [Int],
        incomingIDs: [Int],
        promoting: [Int] = [],
        scope: WindowRecencyScope
    ) -> [Int] {
        let incomingSet = Set(incomingIDs)
        var seenPromoted = Set<Int>()
        let promoted = promoting.filter { seenPromoted.insert($0).inserted }
        let promotingSet = seenPromoted

        let known = recentIDs.filter { incomingSet.contains($0) && !promotingSet.contains($0) }
        let knownSet = Set(known)
        let unknown = incomingIDs.filter { !promotingSet.contains($0) && !knownSet.contains($0) }
        let ordered = promoted + known + unknown

        switch scope {
        case .subset:
            return ordered + recentIDs.filter {
                !incomingSet.contains($0) && !promotingSet.contains($0)
            }
        case .complete:
            return ordered
        }
    }

    /// Subset-listing merge (display-only path). Reorders only the incoming
    /// (current-space) IDs and leaves every other ID exactly where it is:
    /// - Incoming IDs already in `recentIDs` keep their positions (they are
    ///   already in recency order among themselves).
    /// - Incoming IDs not in `recentIDs` (genuinely new windows) are appended
    ///   immediately after the last incoming ID present in `recentIDs`
    ///   (at the end when none are present).
    /// - IDs outside `incomingIDs` (other-space windows) are never relocated,
    ///   so a display-only subset open cannot corrupt the shared MRU order
    ///   (CORR-1). Never used on the commit path — commits promote via
    ///   `merge(promoting:)`.
    static func mergeSubsetListing(recentIDs: [Int], incomingIDs: [Int]) -> [Int] {
        let incomingSet = Set(incomingIDs)
        guard !incomingSet.isEmpty else { return recentIDs }

        let known = recentIDs.filter { incomingSet.contains($0) }
        let knownSet = Set(known)
        let unknown = incomingIDs.filter { !knownSet.contains($0) }
        guard !unknown.isEmpty else { return recentIDs }

        var result = recentIDs
        let insertionIndex = (recentIDs.lastIndex { incomingSet.contains($0) }.map { $0 + 1 })
            ?? result.count
        result.insert(contentsOf: unknown, at: insertionIndex)
        return result
    }
}

extension WindowSwitcherMode {
    var recencyScope: WindowRecencyScope {
        switch self {
        case .currentSpace: .subset
        case .allSpaces: .complete
        }
    }
}
