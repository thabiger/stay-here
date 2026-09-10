import Foundation

public struct SpaceRegistryDerivedState: Equatable {
    public let spaces: [SpaceIdentity]
    public let activeSpaceID: Int?
    public let nativeOrderByDisplay: [String: [Int]]
    public let desktopNumberBySpaceID: [Int: Int]
    public let retainedPreviousSpaces: Bool
    public let isStaleSnapshot: Bool

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        nativeOrderByDisplay: [String: [Int]],
        desktopNumberBySpaceID: [Int: Int],
        retainedPreviousSpaces: Bool = false,
        isStaleSnapshot: Bool = false
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
        self.retainedPreviousSpaces = retainedPreviousSpaces
        self.isStaleSnapshot = isStaleSnapshot
    }
}

enum NextSpacesDecision: Equatable {
    case adopt([SpaceIdentity])
    case staleSnapshot
    case empty
    case retainPrevious
}

public struct SpaceOrderingService {
    public init() {}

    public func deriveState(
        snapshot: CGSBridge.ManagedSnapshot,
        globalActiveID: Int?,
        previousActiveID: Int?,
        previousSpaces: [SpaceIdentity],
        previousNativeOrderByDisplay: [String: [Int]],
        previousDesktopNumberBySpaceID: [Int: Int],
        consecutiveAnomalyRetentions: Int,
        maxConsecutiveAnomalyRetentions: Int
    ) -> SpaceRegistryDerivedState {
        let selectedDisplay = displayForCurrentFocus(snapshot: snapshot, globalActiveID: globalActiveID)
        let discovered = snapshot.spaces.filter { space in
            guard let selectedDisplay else { return true }
            return space.display == selectedDisplay
        }
        let decision = nextSpacesDecision(
            discovered: discovered,
            snapshotIsEmpty: snapshot.spaces.isEmpty,
            previousSpaces: previousSpaces,
            consecutiveAnomalyRetentions: consecutiveAnomalyRetentions,
            maxConsecutiveAnomalyRetentions: maxConsecutiveAnomalyRetentions
        )
        let nextSpaces: [SpaceIdentity] = {
            switch decision {
            case .adopt(let spaces): return spaces
            case .retainPrevious: return previousSpaces
            case .staleSnapshot, .empty: return []
            }
        }()
        let retainedPreviousSpaces = (decision == .retainPrevious)
        let isStaleSnapshot = (decision == .staleSnapshot)

        let metadata = orderingMetadata(
            decision: decision,
            snapshot: snapshot,
            previousNativeOrderByDisplay: previousNativeOrderByDisplay,
            previousDesktopNumberBySpaceID: previousDesktopNumberBySpaceID
        )
        let clampedActive = resolveActiveSpaceID(
            globalActiveID: globalActiveID,
            selectedDisplay: selectedDisplay,
            snapshot: snapshot,
            previousActiveID: previousActiveID,
            nextSpaces: nextSpaces
        )

        return SpaceRegistryDerivedState(
            spaces: nextSpaces,
            activeSpaceID: clampedActive,
            nativeOrderByDisplay: metadata.nativeOrderByDisplay,
            desktopNumberBySpaceID: metadata.desktopNumberBySpaceID,
            retainedPreviousSpaces: retainedPreviousSpaces,
            isStaleSnapshot: isStaleSnapshot
        )
    }

    func nextSpacesDecision(
        discovered: [SpaceIdentity],
        snapshotIsEmpty: Bool,
        previousSpaces: [SpaceIdentity],
        consecutiveAnomalyRetentions: Int,
        maxConsecutiveAnomalyRetentions: Int
    ) -> NextSpacesDecision {
        if !discovered.isEmpty { return .adopt(discovered) }
        if snapshotIsEmpty { return .staleSnapshot }
        if previousSpaces.isEmpty { return .empty }
        if consecutiveAnomalyRetentions >= maxConsecutiveAnomalyRetentions - 1 { return .staleSnapshot }
        return .retainPrevious
    }

    private func orderingMetadata(
        decision: NextSpacesDecision,
        snapshot: CGSBridge.ManagedSnapshot,
        previousNativeOrderByDisplay: [String: [Int]],
        previousDesktopNumberBySpaceID: [Int: Int]
    ) -> (nativeOrderByDisplay: [String: [Int]], desktopNumberBySpaceID: [Int: Int]) {
        if decision == .retainPrevious {
            return (previousNativeOrderByDisplay, previousDesktopNumberBySpaceID)
        }
        let nativeOrderByDisplay = snapshot.orderedIDsByDisplay.mapValues { order in
            order.filter { spaceID in
                snapshot.spaces.first(where: { $0.id == spaceID })?.kind == .desktop
            }
        }
        var rebuiltDesktopNumberBySpaceID: [Int: Int] = [:]
        for order in nativeOrderByDisplay.values {
            for (index, spaceID) in order.enumerated() {
                rebuiltDesktopNumberBySpaceID[spaceID] = index + 1
            }
        }
        return (nativeOrderByDisplay, rebuiltDesktopNumberBySpaceID)
    }

    private func resolveActiveSpaceID(
        globalActiveID: Int?,
        selectedDisplay: String?,
        snapshot: CGSBridge.ManagedSnapshot,
        previousActiveID: Int?,
        nextSpaces: [SpaceIdentity]
    ) -> Int? {
        let firstKnown = selectedDisplay.flatMap { snapshot.activeByDisplay[$0] } ?? snapshot.activeByDisplay.values.first
        let nextActive = globalActiveID ?? firstKnown ?? previousActiveID ?? nextSpaces.first?.id
        return clampActiveSpaceID(nextActive, into: nextSpaces)
    }

    public func orderedSpaceIDs(
        spaces: [SpaceIdentity],
        desktopNumberBySpaceID: [Int: Int]
    ) -> [Int] {
        spaces
            .sorted { desktopSortKey(for: $0.id, desktopNumberBySpaceID: desktopNumberBySpaceID) < desktopSortKey(for: $1.id, desktopNumberBySpaceID: desktopNumberBySpaceID) }
            .map(\.id)
    }

    public func switchableOrderedSpaceIDs(
        spaces: [SpaceIdentity],
        desktopNumberBySpaceID: [Int: Int]
    ) -> [Int] {
        let desktopIDs = Set(spaces.filter { $0.kind == .desktop }.map(\.id))
        return orderedSpaceIDs(
            spaces: spaces,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
        .filter { desktopIDs.contains($0) }
    }

    public func namespaceLabel(
        for spaceID: Int,
        spaces: [SpaceIdentity],
        desktopNumberBySpaceID: [Int: Int]
    ) -> String {
        switch spaces.first(where: { $0.id == spaceID })?.kind {
        case .desktop:
            guard let number = desktopNumberBySpaceID[spaceID] else { return "Desktop ?" }
            return "Desktop \(number)"
        case .fullscreen:
            return "Full Screen"
        case .unknown, .none:
            return "Space"
        }
    }

    public func displayForCurrentFocus(
        snapshot: CGSBridge.ManagedSnapshot,
        globalActiveID: Int?
    ) -> String? {
        if let globalActiveID,
           let display = snapshot.activeByDisplay.first(where: { $0.value == globalActiveID })?.key {
            return display
        }
        return snapshot.activeByDisplay.keys.sorted().first ?? snapshot.spaces.first?.display
    }

    private func clampActiveSpaceID(_ spaceID: Int?, into spaces: [SpaceIdentity]) -> Int? {
        guard let spaceID else { return nil }
        guard let first = spaces.first else { return nil }
        if spaces.contains(where: { $0.id == spaceID }) { return spaceID }
        return first.id
    }

    private func desktopSortKey(
        for spaceID: Int,
        desktopNumberBySpaceID: [Int: Int]
    ) -> (Int, Int) {
        (desktopNumberBySpaceID[spaceID] ?? Int.max, spaceID)
    }
}
