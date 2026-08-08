import AppKit
import Core
import CoreGraphics

@MainActor
final class WindowListProvider {
    private let pipeline: WindowListPipeline
    private let cache: WindowListCache
    private let refresher: AllSpacesCacheRefresher
    private let currentSpaceRefresher: CurrentSpaceCacheRefresher
    private let grouper: WindowGrouper
    private let registry: any SpaceRegistryProtocol
    private let cgsBridge: any CGSBridgeProtocol
    private let settings: WindowSwitcherSettings
    private let focusedWindowIDProvider: WindowListProviderTypes.FocusedWindowIDProvider
    private var lastSettingsVersion: Int?

    var onPerSpaceRefresh: ((WindowSpaceContext) -> Void)?

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
                Self.makeAllSpacesComputer(
                    registry: registry,
                    cgsBridge: cgsBridge,
                    enumerator: enumerator,
                    filter: filter,
                    titleResolver: titleResolver,
                    iconProvider: iconProvider,
                    settings: settings
                )
            },
            onCompletion: { [weak cache] groups, generation in
                cache?.updateAllSpaces(with: groups, generation: generation)
            },
            generationProvider: { [weak cache] in
                cache?.cacheGeneration ?? 0
            }
        )

        self.currentSpaceRefresher = CurrentSpaceCacheRefresher(
            computerFactory: { [weak registry, cgsBridge, enumerator, filter, titleResolver, iconProvider, settings] context in
                Self.makeCurrentSpaceComputer(
                    registry: registry,
                    cgsBridge: cgsBridge,
                    enumerator: enumerator,
                    filter: filter,
                    titleResolver: titleResolver,
                    iconProvider: iconProvider,
                    settings: settings,
                    context: context
                )
            },
            onCompletion: { [weak cache] context, entries, generation in
                cache?.updatePerSpace(with: entries, context: context, generation: generation)
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

        self.currentSpaceRefresher.setNotifyHandler { [weak self] context in
            self?.onPerSpaceRefresh?(context)
        }
    }

    private static func makeAllSpacesComputeContext(
        registry: (any SpaceRegistryProtocol)?,
        cgsBridge: any CGSBridgeProtocol,
        settings: WindowSwitcherSettings
    ) -> AllSpacesWindowComputeContext {
        if registry?.isStaleSnapshot == true {
            return AllSpacesWindowComputeContext(
                currentSpaceID: cgsBridge.activeSpaceID() ?? -1,
                orderedSpaceIDs: [],
                spacesByID: [:],
                spaceNames: [:],
                namespaceLabels: [:],
                showHiddenWindows: settings.windowSwitcherShowHiddenWindows,
                showMinimizedWindows: settings.windowSwitcherShowMinimizedWindows
            )
        }
        let orderedIDs = registry?.orderedSpaceIDs() ?? []
        let spaces = registry?.spaces ?? []
        var names: [Int: String] = [:]
        var labels: [Int: String] = [:]
        for spaceID in orderedIDs {
            names[spaceID] = registry?.name(for: spaceID) ?? SpaceDisplayNameProvider.defaultUnnamedName
            labels[spaceID] = registry?.namespaceLabel(for: spaceID) ?? ""
        }
        return AllSpacesWindowComputeContext(
            currentSpaceID: cgsBridge.activeSpaceID() ?? registry?.activeSpaceID ?? -1,
            orderedSpaceIDs: orderedIDs,
            spacesByID: Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) }),
            spaceNames: names,
            namespaceLabels: labels,
            showHiddenWindows: settings.windowSwitcherShowHiddenWindows,
            showMinimizedWindows: settings.windowSwitcherShowMinimizedWindows
        )
    }

    private static func makeAllSpacesComputer(
        registry: (any SpaceRegistryProtocol)?,
        cgsBridge: any CGSBridgeProtocol,
        enumerator: WindowEnumerator,
        filter: WindowFilter,
        titleResolver: WindowTitleResolver,
        iconProvider: @escaping WindowListProviderTypes.IconProvider,
        settings: WindowSwitcherSettings
    ) -> AllSpacesWindowComputer {
        let context = makeAllSpacesComputeContext(
            registry: registry,
            cgsBridge: cgsBridge,
            settings: settings
        )
        return AllSpacesWindowComputer(
            enumerator: enumerator,
            filter: filter,
            titleResolver: titleResolver,
            iconProvider: iconProvider,
            spacesForWindow: { windowID in cgsBridge.spacesForWindow(windowID: windowID) },
            context: context
        )
    }

    private static func makeCurrentSpaceComputer(
        registry: (any SpaceRegistryProtocol)?,
        cgsBridge: any CGSBridgeProtocol,
        enumerator: WindowEnumerator,
        filter: WindowFilter,
        titleResolver: WindowTitleResolver,
        iconProvider: @escaping WindowListProviderTypes.IconProvider,
        settings: WindowSwitcherSettings,
        context: WindowSpaceContext
    ) -> CurrentSpaceWindowComputer {
        let computeContext = CurrentSpaceWindowComputeContext(
            spaceID: context.spaceID,
            desktopNumber: context.desktopNumber,
            showHiddenWindows: settings.windowSwitcherShowHiddenWindows,
            showMinimizedWindows: settings.windowSwitcherShowMinimizedWindows
        )
        return CurrentSpaceWindowComputer(
            enumerator: enumerator,
            filter: filter,
            titleResolver: titleResolver,
            iconProvider: iconProvider,
            spacesForWindow: { windowID in cgsBridge.spacesForWindow(windowID: windowID) },
            context: computeContext
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
        refreshCurrentSpaceCacheInBackground(context: context)
        return []
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

    func refreshCurrentSpaceCacheInBackground() {
        guard let context = currentContext() else { return }
        currentSpaceRefresher.refresh(context: context)
    }

    func refreshCurrentSpaceCacheInBackground(context: WindowSpaceContext) {
        currentSpaceRefresher.refresh(context: context)
    }

    func cancelCurrentSpaceRefresh() {
        currentSpaceRefresher.cancel()
    }

    func waitForCurrentSpaceRefresh() async {
        await currentSpaceRefresher.waitForIdle()
    }
}
