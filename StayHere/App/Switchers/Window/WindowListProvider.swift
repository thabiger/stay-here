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

        // ARCH-1: local variable captured by reference in onCompletion; set after
        // refresher is assigned so [weak self] is not needed during init.
        var allSpacesRefreshTrigger: (() -> Void)?

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
                guard let cache else { return }
                if !cache.updateAllSpaces(with: groups, generation: generation) {
                    // ARCH-1: a refresh dispatched before invalidate() completed late and
                    // its stale result was discarded. Re-dispatch with the current
                    // generation so the cache self-heals to full AX titles — guaranteed,
                    // not best-effort. refresh() coalesces: .idle -> start (fresh
                    // generation), .refreshing -> .pending (handleCompletion re-dispatches
                    // with a fresh generation), .pending -> no-op (follow-up queued).
                    allSpacesRefreshTrigger?()
                }
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

        // ARCH-1: set the re-kick trigger after all stored properties are initialized.
        allSpacesRefreshTrigger = { [weak self] in self?.refreshAllSpacesCacheInBackground() }
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
        // PERF-2: skip AX title resolution in the inline fallback to avoid
        // main-thread blocking. Windows with empty CGWindow names will show
        // nil titles (rendered as app name). A background refresh is kicked
        // below to self-heal titles for the next open.
        let entries = pipeline.buildEntriesForAllSpaces(from: rawWindows, currentSpaceID: currentSpaceID, resolveAccessibilityTitles: false)

        let groups = grouper.groupWindows(entries)
        // Note: Direct inline build always accepted (fresh data, current generation).
        // The background refresh path is generation-guarded and re-kicks on stale
        // discard so self-heal is guaranteed, not best-effort (ARCH-1).
        cache.updateAllSpaces(with: groups, generation: cache.cacheGeneration)
        // Kick background refresh so titles self-heal to AX quality for the next open.
        refreshAllSpacesCacheInBackground()
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
