import AppKit
import Core

/// Snapshot of the main-actor state needed to compute the all-spaces window
/// list off the main thread. Captured on main in
/// `WindowListProvider.makeAllSpacesComputeContext()`.
struct AllSpacesWindowComputeContext {
    let currentSpaceID: Int
    let orderedSpaceIDs: [Int]
    let spacesByID: [Int: SpaceIdentity]
    let spaceNames: [Int: String]
    let namespaceLabels: [Int: String]
    /// Settings snapshotted on the main actor so the background path never
    /// reads the shared mutable `WindowFilter.settings` reference.
    let showHiddenWindows: Bool
    let showMinimizedWindows: Bool
}

/// All members are stateless. AX calls (via `titleResolver`) are serialized
/// through a dedicated queue inside `WindowTitleResolver.live(pid:)`, so crossing
/// to a background queue is safe despite the compiler being unable to verify
/// Sendability.
extension AllSpacesWindowComputer: @unchecked Sendable {}

/// Non-isolated computer for the all-spaces window list. All referenced helpers
/// (`WindowEnumerator`, `WindowFilter`, `WindowTitleResolver`, icon provider,
/// CGS `spacesForWindow`) are stateless and thread-safe, so `compute()` can run
/// on a background queue. The result is swapped into the cache on main by
/// `WindowListProvider.refreshAllSpacesCacheInBackground()`.
struct AllSpacesWindowComputer {
    let enumerator: WindowEnumerator
    let filter: WindowFilter
    let titleResolver: WindowTitleResolver
    let iconProvider: WindowListProviderTypes.IconProvider
    let spacesForWindow: (Int) -> [Int]
    let context: AllSpacesWindowComputeContext

    func compute() -> [SpaceWindowGroup] {
        let rawWindows = enumerator.enumerate()
        let filtered = filter.filterForAllSpaces(
            rawWindows,
            currentSpaceID: context.currentSpaceID,
            showHiddenWindows: context.showHiddenWindows,
            showMinimizedWindows: context.showMinimizedWindows
        )

        let withTitles = titleResolver.resolveTitles(for: filtered) { _ in nil }

        let preResolvedSpaceIDs = Dictionary(
            filtered.map { ($0.windowID, $0.spaceIDs) },
            uniquingKeysWith: { first, _ in first }
        )

        let entries = withTitles.map { window in
            WindowEntry(
                windowID: window.windowID,
                pid: window.pid,
                appName: window.appName,
                windowTitle: window.windowTitle,
                icon: iconProvider(window.application)
            )
        }

        return WindowSpaceGrouping.groupWindows(
            entries,
            orderedSpaceIDs: context.orderedSpaceIDs,
            spacesByID: context.spacesByID,
            spacesForWindow: spacesForWindow,
            nameProvider: { context.spaceNames[$0] ?? SpaceDisplayNameProvider.defaultUnnamedName },
            namespaceLabelProvider: { context.namespaceLabels[$0] ?? "" },
            preResolvedSpaceIDs: preResolvedSpaceIDs
        )
    }
}
