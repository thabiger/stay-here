import AppKit
import Core

struct WindowListPipeline {
    let enumerator: WindowEnumerator
    let filter: WindowFilter
    let titleResolver: WindowTitleResolver
    let iconProvider: WindowListProviderTypes.IconProvider

    func buildEntries(from rawWindows: [RawWindowInfo], in filterContext: FilterContext) -> [WindowEntry] {
        let filtered = filter.filter(rawWindows, in: filterContext)
        let withTitles = titleResolver.resolveTitles(for: filtered) { _ in nil }
        return withTitles.map { window in
            WindowEntry(
                windowID: window.windowID,
                pid: window.pid,
                appName: window.appName,
                windowTitle: window.windowTitle,
                icon: iconProvider(window.application)
            )
        }
    }

    func buildEntriesForAllSpaces(from rawWindows: [RawWindowInfo], currentSpaceID: Int, resolveAccessibilityTitles: Bool = true) -> (entries: [WindowEntry], preResolvedSpaceIDs: [Int: [Int]]) {
        let filtered = filter.filterForAllSpaces(rawWindows, currentSpaceID: currentSpaceID)
        let preResolvedSpaceIDs = Dictionary(
            filtered.map { ($0.windowID, $0.spaceIDs) },
            uniquingKeysWith: { first, _ in first }
        )
        let withTitles = titleResolver.resolveTitles(for: filtered, fallbackNameProvider: { _ in nil }, includeAccessibilityTitles: resolveAccessibilityTitles)
        let entries = withTitles.map { window in
            WindowEntry(
                windowID: window.windowID,
                pid: window.pid,
                appName: window.appName,
                windowTitle: window.windowTitle,
                icon: iconProvider(window.application)
            )
        }
        return (entries: entries, preResolvedSpaceIDs: preResolvedSpaceIDs)
    }
}
