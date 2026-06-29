import AppKit
import ApplicationServices
import Core
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
final class WindowListProvider {
    struct SpaceWindowGroup {
        let spaceID: Int
        let spaceLabel: String
        let entries: [WindowEntry]
    }

    typealias WindowInfoProvider = @MainActor () -> [[String: Any]]?
    typealias RunningApplicationProvider = @MainActor (pid_t) -> (any WindowListApplication)?
    typealias AccessibilityWindowTitlesProvider = @MainActor (pid_t) -> [Int: String]
    typealias FocusedWindowIDProvider = @MainActor () -> Int?
    typealias IconProvider = @MainActor ((any WindowListApplication)?) -> NSImage

    private let enumerator: WindowEnumerator
    private let filter: WindowFilter
    private let titleResolver: WindowTitleResolver
    private let iconProvider: IconProvider
    private let grouper: WindowGrouper
    private let registry: any SpaceRegistryProtocol
    private let cgsBridge: any CGSBridgeProtocol
    private let settings: WindowSwitcherSettings
    private let focusedWindowIDProvider: FocusedWindowIDProvider
    private var cachedEntriesContext: WindowSpaceContext?
    private var cachedEntries: [WindowEntry]?
    private var cachedAllSpacesEntries: [SpaceWindowGroup]?

    init(
        registry: any SpaceRegistryProtocol,
        cgsBridge: any CGSBridgeProtocol,
        settings: WindowSwitcherSettings,
        windowInfoProvider: @escaping WindowInfoProvider = WindowListProvider.liveWindowInfoProvider,
        runningApplicationProvider: @escaping RunningApplicationProvider = WindowListProvider.liveRunningApplicationProvider,
        accessibilityWindowTitlesProvider: @escaping AccessibilityWindowTitlesProvider = WindowListProvider.liveAccessibilityWindowTitlesProvider,
        focusedWindowIDProvider: @escaping FocusedWindowIDProvider = WindowListProvider.liveFocusedWindowIDProvider,
        iconProvider: @escaping IconProvider = WindowListProvider.liveIconProvider
    ) {
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.settings = settings
        self.focusedWindowIDProvider = focusedWindowIDProvider

        self.enumerator = WindowEnumerator(provider: windowInfoProvider)
        self.filter = WindowFilter(
            settings: settings,
            runningApplicationProvider: runningApplicationProvider,
            spacesForWindow: { windowID in
                cgsBridge.spacesForWindow(windowID: windowID)
            }
        )
        self.titleResolver = WindowTitleResolver(titleProvider: accessibilityWindowTitlesProvider)
        self.iconProvider = iconProvider
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
        if cachedEntriesContext == context, let cached = cachedEntries {
            return cached
        }

        let rawWindows = enumerator.enumerate()
        let filterContext = FilterContext(spaceID: context.spaceID, desktopNumber: context.desktopNumber)
        let filtered = filter.filter(rawWindows, in: filterContext)

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

        cachedEntriesContext = context
        cachedEntries = entries
        return entries
    }

    func focusedWindowID() -> Int? {
        focusedWindowIDProvider()
    }

    func entriesForAllSpaces() -> [SpaceWindowGroup] {
        if let cached = cachedAllSpacesEntries {
            return cached
        }

        let rawWindows = enumerator.enumerate()
        let currentSpaceID = cgsBridge.activeSpaceID() ?? registry.activeSpaceID ?? -1
        let filtered = filter.filterForAllSpaces(rawWindows, currentSpaceID: currentSpaceID)

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

        let groups = grouper.groupWindows(entries)
        cachedAllSpacesEntries = groups
        return groups
    }

    func invalidateCache() {
        cachedEntriesContext = nil
        cachedEntries = nil
        cachedAllSpacesEntries = nil
    }

    private static func liveWindowInfoProvider() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    }

    private static func liveRunningApplicationProvider(pid: pid_t) -> (any WindowListApplication)? {
        NSRunningApplication(processIdentifier: pid)
    }

    private static func liveAccessibilityWindowTitlesProvider(pid: pid_t) -> [Int: String] {
        WindowTitleResolver.live(pid: pid)
    }

    private static func liveFocusedWindowIDProvider() -> Int? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
              let window = windowRef else {
            return nil
        }

        var numberRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            "AXWindowNumber" as CFString,
            &numberRef
        ) == .success,
              let number = numberRef as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private static func liveIconProvider(application: (any WindowListApplication)?) -> NSImage {
        WindowIconProvider().icon(for: application)
    }
}
