import Foundation

public struct SpaceRegistryDerivedState: Equatable {
    public let spaces: [SpaceIdentity]
    public let activeSpaceID: Int?
    public let nativeOrderByDisplay: [String: [Int]]
    public let desktopNumberBySpaceID: [Int: Int]
    public let retainedPreviousSpaces: Bool

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        nativeOrderByDisplay: [String: [Int]],
        desktopNumberBySpaceID: [Int: Int],
        retainedPreviousSpaces: Bool = false
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
        self.retainedPreviousSpaces = retainedPreviousSpaces
    }
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
        let nextSpaces: [SpaceIdentity]
        let retainedPreviousSpaces: Bool
        if !discovered.isEmpty {
            nextSpaces = discovered
            retainedPreviousSpaces = false
        } else if snapshot.spaces.isEmpty {
            nextSpaces = fallbackSpaces()
            retainedPreviousSpaces = false
        } else if previousSpaces.isEmpty {
            nextSpaces = []
            retainedPreviousSpaces = false
        } else if consecutiveAnomalyRetentions >= maxConsecutiveAnomalyRetentions - 1 {
            nextSpaces = fallbackSpaces()
            retainedPreviousSpaces = false
        } else {
            nextSpaces = previousSpaces
            retainedPreviousSpaces = true
        }

        let nativeOrderByDisplay: [String: [Int]]
        let desktopNumberBySpaceID: [Int: Int]
        if retainedPreviousSpaces {
            nativeOrderByDisplay = previousNativeOrderByDisplay
            desktopNumberBySpaceID = previousDesktopNumberBySpaceID
        } else {
            nativeOrderByDisplay = snapshot.orderedIDsByDisplay.mapValues { order in
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
            desktopNumberBySpaceID = rebuiltDesktopNumberBySpaceID
        }

        let firstKnown = selectedDisplay.flatMap { snapshot.activeByDisplay[$0] } ?? snapshot.activeByDisplay.values.first
        let nextActive = globalActiveID ?? firstKnown ?? previousActiveID ?? nextSpaces.first?.id
        let clampedActive = clampActiveSpaceID(nextActive, into: nextSpaces)

        return SpaceRegistryDerivedState(
            spaces: nextSpaces,
            activeSpaceID: clampedActive,
            nativeOrderByDisplay: nativeOrderByDisplay,
            desktopNumberBySpaceID: desktopNumberBySpaceID,
            retainedPreviousSpaces: retainedPreviousSpaces
        )
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

    public static let fallbackDisplay = "fallback-display"

    public static func isSyntheticFallback(_ space: SpaceIdentity) -> Bool {
        space.display == fallbackDisplay
    }

    public static func containsSyntheticFallback(_ spaces: [SpaceIdentity]) -> Bool {
        spaces.isEmpty || spaces.contains(where: { isSyntheticFallback($0) })
    }

    private func fallbackSpaces() -> [SpaceIdentity] {
        [SpaceIdentity(id: 1, display: Self.fallbackDisplay)]
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
