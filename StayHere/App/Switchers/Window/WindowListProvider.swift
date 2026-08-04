import AppKit
import Core
import CoreGraphics

@MainActor
final class WindowListProvider {
    private let pipeline: WindowListPipeline
    private let cache: WindowListCache
    private let refresher: AllSpacesCacheRefresher
    private let grouper: WindowGrouper
    private let registry: any SpaceRegistryProtocol
    private let cgsBridge: any CGSBridgeProtocol
    private let settings: WindowSwitcherSettings
    private let focusedWindowIDProvider: WindowListProviderTypes.FocusedWindowIDProvider
    private var lastSettingsVersion: Int?

    init(
        registry: any SpaceRegistryProtocol,
        cgsBridge: any CGSBridgeProtocol,
        settings: WindowSwitcherSettings,
        windowInfoProvider: @escaping WindowListProviderTypes.WindowInfoProvider = WindowListProviderTypes.liveWindowInfoProvider,
        runningApplicationProvider: @escaping WindowListProviderTypes.RunningApplicationProvider = WindowListProviderTypes.liveRunningApplicationProvider,
        accessibilityWindowTitlesProvider: @escaping WindowListProviderTypes.AccessibilityWindowTitlesProvider = WindowListProviderTypes.liveAccessibilityWindowTitlesProvider,
        focusedWindowIDProvider: @escaping WindowListProviderTypes.FocusedWindowIDProvider = WindowListProviderTypes.liveFocusedWindowIDProvider,
        iconProvider: @escaping WindowListProviderTypes.IconProvider = WindowListProviderTypes.liveIconProvider
    ) {
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.settings = settings
        self.focusedWindowIDProvider = focusedWindowIDProvider

        let enumerator = WindowEnumerator(provider: windowInfoProvider)
        let filter = WindowFilter(
            settings: settings,
            runningApplicationProvider: runningApplicationProvider,
            spacesForWindow: { windowID in
                cgsBridge.spacesForWindow(windowID: windowID)
            }
        )
        let titleResolver = WindowTitleResolver(titleProvider: accessibilityWindowTitlesProvider)

        self.pipeline = WindowListPipeline(
            enumerator: enumerator,
            filter: filter,
            titleResolver: titleResolver,
            iconProvider: iconProvider
        )

        self.cache = WindowListCache()

        self.refresher = AllSpacesCacheRefresher(
            computerFactory: { [weak registry, cgsBridge, enumerator, filter, titleResolver, iconProvider, settings] in
                let orderedIDs = registry?.orderedSpaceIDs() ?? []
                let spaces = registry?.spaces ?? []
                var names: [Int: String] = [:]
                var labels: [Int: String] = [:]
                for spaceID in orderedIDs {
                    names[spaceID] = registry?.name(for: spaceID) ?? SpaceDisplayNameProvider.defaultUnnamedName
                    labels[spaceID] = registry?.namespaceLabel(for: spaceID) ?? ""
                }
                let context = AllSpacesWindowComputeContext(
                    currentSpaceID: cgsBridge.activeSpaceID() ?? registry?.activeSpaceID ?? -1,
                    orderedSpaceIDs: orderedIDs,
                    spacesByID: Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) }),
                    spaceNames: names,
                    namespaceLabels: labels,
                    showHiddenWindows: settings.windowSwitcherShowHiddenWindows,
                    showMinimizedWindows: settings.windowSwitcherShowMinimizedWindows
                )
                return AllSpacesWindowComputer(
                    enumerator: enumerator,
                    filter: filter,
                    titleResolver: titleResolver,
                    iconProvider: iconProvider,
                    spacesForWindow: { windowID in cgsBridge.spacesForWindow(windowID: windowID) },
                    context: context
                )
            },
            onCompletion: { [weak cache] groups, generation in
                cache?.updateAllSpaces(with: groups, generation: generation)
            },
            generationProvider: { [weak cache] in
                cache?.cacheGeneration ?? 0
            }
        )

        self.grouper = WindowGrouper(
            orderedSpaceIDs: { [weak registry] in registry?.orderedSpaceIDs() ?? [] },
            spacesByID: { [weak registry] in
                Dictionary(uniqueKeysWithValues: (registry?.spaces ?? []).map { ($0.id, $0) })
            },
            spacesForWindow: { windowID in
                cgsBridge.spacesForWindow(windowID: windowID)
            },
            nameProvider: { [weak registry] spaceID in
                registry?.name(for: spaceID) ?? SpaceDisplayNameProvider.defaultUnnamedName
            },
            namespaceLabelProvider: { [weak registry] spaceID in
                registry?.namespaceLabel(for: spaceID) ?? ""
            }
        )
    }

    private var settingsVersion: Int {
        var hasher = Hasher()
        hasher.combine(settings.windowSwitcherShowHiddenWindows)
        hasher.combine(settings.windowSwitcherShowMinimizedWindows)
        return hasher.finalize()
    }

    private func invalidateCacheIfSettingsChanged() {
        let version = settingsVersion
        guard let lastSettingsVersion else {
            self.lastSettingsVersion = version
            return
        }
        guard lastSettingsVersion != version else { return }
        self.lastSettingsVersion = version
        cache.invalidate()
    }

    func currentContext() -> WindowSpaceContext? {
        let snapshot = cgsBridge.managedSnapshot()
        guard let activeSpaceID = cgsBridge.activeSpaceID()
            ?? registry.activeSpaceID
            ?? snapshot.activeByDisplay.values.first else {
            return nil
        }

        let display = snapshot.spaces.first(where: { $0.id == activeSpaceID })?.display
            ?? snapshot.activeByDisplay.first(where: { $0.value == activeSpaceID })?.key

        let desktopNumber = display.flatMap { displayID in
            snapshot.orderedIDsByDisplay[displayID]?.firstIndex(of: activeSpaceID).map { $0 + 1 }
        }

        return WindowSpaceContext(spaceID: activeSpaceID, desktopNumber: desktopNumber)
    }

    func entries(in context: WindowSpaceContext) -> [WindowEntry] {
        invalidateCacheIfSettingsChanged()
        if let cached = cache.perSpaceHit(for: context) {
            return cached
        }

        let rawWindows = pipeline.enumerator.enumerate()
        let filterContext = FilterContext(spaceID: context.spaceID, desktopNumber: context.desktopNumber)
        let entries = pipeline.buildEntries(from: rawWindows, in: filterContext)

        cache.updatePerSpace(with: entries, context: context)
        return entries
    }

    func focusedWindowID() -> Int? {
        focusedWindowIDProvider()
    }

    func entriesForAllSpaces() -> [SpaceWindowGroup] {
        invalidateCacheIfSettingsChanged()
        if let cached = cache.allSpacesHit() {
            return cached
        }

        let rawWindows = pipeline.enumerator.enumerate()
        let currentSpaceID = cgsBridge.activeSpaceID() ?? registry.activeSpaceID ?? -1
        let entries = pipeline.buildEntriesForAllSpaces(from: rawWindows, currentSpaceID: currentSpaceID)

        let groups = grouper.groupWindows(entries)
        // Note: Direct inline build bypasses generation check. Only the
        // background refresh path uses the generation counter to protect
        // against stale completions post-invalidation.
        cache.updateAllSpaces(with: groups, generation: cache.cacheGeneration)
        return groups
    }

    func invalidateCache() {
        cache.invalidate()
    }

    func refreshAllSpacesCacheInBackground() {
        refresher.refresh()
    }

    func cancelAllSpacesRefresh() {
        refresher.cancel()
    }

    func waitForAllSpacesRefresh() async {
        await refresher.waitForIdle()
    }
}
