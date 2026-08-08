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

    func buildEntriesForAllSpaces(from rawWindows: [RawWindowInfo], currentSpaceID: Int, resolveAccessibilityTitles: Bool = true) -> [WindowEntry] {
        let filtered = filter.filterForAllSpaces(rawWindows, currentSpaceID: currentSpaceID)
        let withTitles = titleResolver.resolveTitles(for: filtered, fallbackNameProvider: { _ in nil }, includeAccessibilityTitles: resolveAccessibilityTitles)
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
}
