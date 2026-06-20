import AppKit
import ApplicationServices
import Core
import CoreGraphics
import UniformTypeIdentifiers

protocol WindowListApplication {
    var isHidden: Bool { get }
    var localizedName: String? { get }
    var bundleURL: URL? { get }
}

extension NSRunningApplication: WindowListApplication {}

final class WindowListProvider {
    typealias WindowInfoProvider = () -> [[String: Any]]?
    typealias RunningApplicationProvider = (pid_t) -> (any WindowListApplication)?
    typealias AccessibilityWindowTitlesProvider = (pid_t) -> [Int: String]
    typealias FocusedWindowIDProvider = () -> Int?
    typealias IconProvider = ((any WindowListApplication)?) -> NSImage

    private let registry: SpaceRegistry
    private let cgsBridge: any CGSBridgeProtocol
    private let settings: SettingsRepository
    private let windowInfoProvider: WindowInfoProvider
    private let runningApplicationProvider: RunningApplicationProvider
    private let accessibilityWindowTitlesProvider: AccessibilityWindowTitlesProvider
    private let focusedWindowIDProvider: FocusedWindowIDProvider
    private let iconProvider: IconProvider

    init(
        registry: SpaceRegistry,
        cgsBridge: any CGSBridgeProtocol,
        settings: SettingsRepository,
        windowInfoProvider: @escaping WindowInfoProvider = WindowListProvider.liveWindowInfoProvider,
        runningApplicationProvider: @escaping RunningApplicationProvider = WindowListProvider.liveRunningApplicationProvider,
        accessibilityWindowTitlesProvider: @escaping AccessibilityWindowTitlesProvider = WindowListProvider.liveAccessibilityWindowTitlesProvider,
        focusedWindowIDProvider: @escaping FocusedWindowIDProvider = WindowListProvider.liveFocusedWindowIDProvider,
        iconProvider: @escaping IconProvider = WindowListProvider.liveIconProvider
    ) {
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.settings = settings
        self.windowInfoProvider = windowInfoProvider
        self.runningApplicationProvider = runningApplicationProvider
        self.accessibilityWindowTitlesProvider = accessibilityWindowTitlesProvider
        self.focusedWindowIDProvider = focusedWindowIDProvider
        self.iconProvider = iconProvider
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
        guard let raw = windowInfoProvider() else { return [] }
        var accessibilityTitleCache: [pid_t: [Int: String]] = [:]

        return raw.compactMap { item in
            guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let windowNumber = item[kCGWindowNumber as String] as? NSNumber,
                  let layer = item[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0 else {
                return nil
            }

            if let workspace = (item["kCGWindowWorkspace"] as? NSNumber)?.intValue,
               let desktopNumber = context.desktopNumber,
               workspace != desktopNumber {
                return nil
            }

            if (item["kCGWindowWorkspace"] as? NSNumber) == nil {
                let spaceIDs = cgsBridge.spacesForWindow(windowID: windowNumber.intValue)
                guard spaceIDs.contains(context.spaceID) else { return nil }
            }

            let pid = owner.int32Value
            let application = runningApplicationProvider(pid)
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            if application?.isHidden == true {
                if !settings.windowSwitcherShowHiddenWindows {
                    return nil
                }
            } else if !isOnScreen && !settings.windowSwitcherShowMinimizedWindows {
                return nil
            }

            let appName = application?.localizedName
                ?? (item[kCGWindowOwnerName as String] as? String)
                ?? "App"
            let windowTitle = title(for: item) ?? accessibilityTitle(
                for: pid,
                windowNumber: windowNumber.intValue,
                cache: &accessibilityTitleCache
            )
            return WindowEntry(
                windowID: windowNumber.intValue,
                pid: pid,
                appName: appName,
                windowTitle: windowTitle,
                icon: iconProvider(application)
            )
        }
    }

    func focusedWindowID() -> Int? {
        focusedWindowIDProvider()
    }

    struct SpaceWindowGroup {
        let spaceID: Int
        let spaceLabel: String
        let entries: [WindowEntry]
    }

    func entriesForAllSpaces() -> [SpaceWindowGroup] {
        guard let raw = windowInfoProvider() else { return [] }
        var accessibilityTitleCache: [pid_t: [Int: String]] = [:]

        let orderedSpaceIDs = registry.orderedSpaceIDs()
        let spacesByID = Dictionary(uniqueKeysWithValues: registry.spaces.map { ($0.id, $0) })

        var windowsBySpace: [Int: [WindowEntry]] = [:]

        for item in raw {
            guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let windowNumber = item[kCGWindowNumber as String] as? NSNumber,
                  let layer = item[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0 else {
                continue
            }

            let pid = owner.int32Value
            let application = runningApplicationProvider(pid)

            // Filter hidden apps (respect the user setting)
            if application?.isHidden == true,
               !settings.windowSwitcherShowHiddenWindows {
                continue
            }

            // For non-active spaces, kCGWindowIsOnscreen is false even for normal
            // windows. Only filter minimized/off-screen windows on the current space.
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            if !isOnScreen && !settings.windowSwitcherShowMinimizedWindows {
                let spaceIDs = cgsBridge.spacesForWindow(windowID: windowNumber.intValue)
                let isOnCurrentSpace = spaceIDs.contains(
                    cgsBridge.activeSpaceID() ?? registry.activeSpaceID ?? -1
                )
                if isOnCurrentSpace {
                    // Minimized window on current space — respect the setting
                    continue
                }
                // Window on another space — include it (it's not minimized, just off-screen)
            }

            let appName = application?.localizedName
                ?? (item[kCGWindowOwnerName as String] as? String)
                ?? "App"
            let windowTitle = title(for: item) ?? accessibilityTitle(
                for: pid,
                windowNumber: windowNumber.intValue,
                cache: &accessibilityTitleCache
            )
            let entry = WindowEntry(
                windowID: windowNumber.intValue,
                pid: pid,
                appName: appName,
                windowTitle: windowTitle,
                icon: iconProvider(application)
            )

            let spaceIDs = cgsBridge.spacesForWindow(windowID: windowNumber.intValue)
            if let primarySpaceID = spaceIDs.first(where: { orderedSpaceIDs.contains($0) })
                ?? spaceIDs.first {
                windowsBySpace[primarySpaceID, default: []].append(entry)
            }
        }

        var groups: [SpaceWindowGroup] = []
        for spaceID in orderedSpaceIDs {
            guard let entries = windowsBySpace[spaceID], !entries.isEmpty else { continue }
            let space = spacesByID[spaceID]
            let label = registry.name(for: spaceID)
            let systemName = space?.systemName
            let displayLabel: String
            if label != "Unnamed space" {
                displayLabel = label
            } else if let systemName, !systemName.isEmpty {
                displayLabel = systemName
            } else {
                displayLabel = registry.namespaceLabel(for: spaceID)
            }
            groups.append(SpaceWindowGroup(
                spaceID: spaceID,
                spaceLabel: displayLabel,
                entries: entries
            ))
        }

        return groups
    }

    private func title(for item: [String: Any]) -> String? {
        let raw = (item[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func accessibilityTitle(
        for pid: pid_t,
        windowNumber: Int,
        cache: inout [pid_t: [Int: String]]
    ) -> String? {
        if let cached = cache[pid] {
            return cached[windowNumber]
        }

        let titles = accessibilityWindowTitlesProvider(pid)
        cache[pid] = titles
        return titles[windowNumber]
    }

    private static func liveWindowInfoProvider() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    }

    private static func liveRunningApplicationProvider(pid: pid_t) -> (any WindowListApplication)? {
        NSRunningApplication(processIdentifier: pid)
    }

    private static func liveAccessibilityWindowTitlesProvider(pid: pid_t) -> [Int: String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return [:]
        }

        var titles: [Int: String] = [:]
        for window in windows {
            var numberRef: CFTypeRef?
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberRef) == .success,
                  let number = numberRef as? NSNumber,
                  AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            titles[number.intValue] = trimmed
        }
        return titles
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
        if let bundleURL = application?.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }

        let icon = NSWorkspace.shared.icon(for: UTType.application)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}
