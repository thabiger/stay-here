import Foundation

public struct SpaceRegistryDerivedState: Equatable {
    public let spaces: [SpaceIdentity]
    public let activeSpaceID: Int?
    public let nativeOrderByDisplay: [String: [Int]]
    public let desktopNumberBySpaceID: [Int: Int]

    public init(
        spaces: [SpaceIdentity],
        activeSpaceID: Int?,
        nativeOrderByDisplay: [String: [Int]],
        desktopNumberBySpaceID: [Int: Int]
    ) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.nativeOrderByDisplay = nativeOrderByDisplay
        self.desktopNumberBySpaceID = desktopNumberBySpaceID
    }
}

public struct SpaceOrderingService {
    public init() {}

    public func deriveState(
        snapshot: CGSBridge.ManagedSnapshot,
        globalActiveID: Int?,
        previousActiveID: Int?
    ) -> SpaceRegistryDerivedState {
        let selectedDisplay = displayForCurrentFocus(snapshot: snapshot, globalActiveID: globalActiveID)
        let discovered = snapshot.spaces.filter { space in
            guard let selectedDisplay else { return true }
            return space.display == selectedDisplay
        }
        let nextSpaces = discovered.isEmpty ? fallbackSpaces() : discovered
        let nativeOrderByDisplay = snapshot.orderedIDsByDisplay.mapValues { order in
            order.filter { spaceID in
                snapshot.spaces.first(where: { $0.id == spaceID })?.kind == .desktop
            }
        }

        var desktopNumberBySpaceID: [Int: Int] = [:]
        for order in nativeOrderByDisplay.values {
            for (index, spaceID) in order.enumerated() {
                desktopNumberBySpaceID[spaceID] = index + 1
            }
        }

        let firstKnown = selectedDisplay.flatMap { snapshot.activeByDisplay[$0] } ?? snapshot.activeByDisplay.values.first
        let nextActive = globalActiveID ?? firstKnown ?? previousActiveID ?? nextSpaces.first?.id

        return SpaceRegistryDerivedState(
            spaces: nextSpaces,
            activeSpaceID: nextActive,
            nativeOrderByDisplay: nativeOrderByDisplay,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
    }

    public func orderedSpaceIDs(
        spaces: [SpaceIdentity],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool,
        desktopNumberBySpaceID: [Int: Int]
    ) -> [Int] {
        let desktopOrderedIDs = spaces
            .sorted { desktopSortKey(for: $0.id, desktopNumberBySpaceID: desktopNumberBySpaceID) < desktopSortKey(for: $1.id, desktopNumberBySpaceID: desktopNumberBySpaceID) }
            .map(\.id)

        guard usesCustomDisplayOrder else {
            return desktopOrderedIDs
        }

        let validIDs = Set(spaces.map(\.id))
        var ids = displayOrder.filter { validIDs.contains($0) }
        for id in desktopOrderedIDs where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    public func switchableOrderedSpaceIDs(
        spaces: [SpaceIdentity],
        displayOrder: [Int],
        usesCustomDisplayOrder: Bool,
        desktopNumberBySpaceID: [Int: Int]
    ) -> [Int] {
        let switchableIDs = Set(
            spaces
                .filter { $0.kind == .desktop }
                .map(\.id)
        )
        return orderedSpaceIDs(
            spaces: spaces,
            displayOrder: displayOrder,
            usesCustomDisplayOrder: usesCustomDisplayOrder,
            desktopNumberBySpaceID: desktopNumberBySpaceID
        )
        .filter { switchableIDs.contains($0) }
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

    private func fallbackSpaces() -> [SpaceIdentity] {
        [SpaceIdentity(id: 1, display: "fallback-display")]
    }

    private func desktopSortKey(
        for spaceID: Int,
        desktopNumberBySpaceID: [Int: Int]
    ) -> (Int, Int) {
        (desktopNumberBySpaceID[spaceID] ?? Int.max, spaceID)
    }
}
