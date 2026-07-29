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
}

/// All members are stateless and thread-safe by design (CGWindowList / AX /
/// NSRunningApplication / NSWorkspace / CGS calls), so crossing to a background
/// queue is safe despite the compiler being unable to verify Sendability.
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
    let iconProvider: WindowListProvider.IconProvider
    let spacesForWindow: (Int) -> [Int]
    let context: AllSpacesWindowComputeContext

    func compute() -> [SpaceWindowGroup] {
        let rawWindows = enumerator.enumerate()
        let filtered = filter.filterForAllSpaces(rawWindows, currentSpaceID: context.currentSpaceID)

        let withTitles = titleResolver.resolveTitles(for: filtered) { _ in nil }

        let entries = withTitles.map { window in
            WindowEntry(
                windowID: window.windowID,
                pid: window.pid,
                appName: window.appName,
                windowTitle: window.windowTitle,
                icon: iconProvider(filtered.first(where: { $0.windowID == window.windowID })?.application)
            )
        }

        return WindowSpaceGrouping.groupWindows(
            entries,
            orderedSpaceIDs: context.orderedSpaceIDs,
            spacesByID: context.spacesByID,
            spacesForWindow: spacesForWindow,
            nameProvider: { context.spaceNames[$0] ?? SpaceDisplayNameProvider.defaultUnnamedName },
            namespaceLabelProvider: { context.namespaceLabels[$0] ?? "" }
        )
    }
}
