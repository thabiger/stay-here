import AppKit
import ApplicationServices
import CoreGraphics
import Core
import SwiftUI
import UniformTypeIdentifiers

final class WindowSwitcherController {
    private struct Session {
        let startingWindowID: Int?
        var selectedWindowID: Int?
        let shortcut: SpaceSwitcherShortcut
        /// Cached window list snapshot taken when the session opened.
        /// Stored in the session to avoid re-running the expensive
        /// `CGWindowListCopyWindowInfo` WindowServer round-trip on every
        /// keypress / panel update.
        let entries: [WindowEntry]
        let spaceContext: SpaceContext

        var didChangeSelection: Bool {
            selectedWindowID != nil && selectedWindowID != startingWindowID
        }
    }

    struct WindowEntry {
        let windowID: Int
        let pid: pid_t
        let appName: String
        let windowTitle: String?
        let icon: NSImage
    }

    private struct SpaceContext {
        let spaceID: Int
        let desktopNumber: Int?
    }

    private let registry: SpaceRegistry
    private let cgsBridge: any CGSBridgeProtocol
    private let settings: SettingsRepository
    private let shortcutProvider: () -> SpaceSwitcherShortcut

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session: Session?
    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)?

    internal var hasActiveSession: Bool { session != nil }

    /// Test seam — exposes the cached window list from the active session.
    /// Returns `nil` if no session is active.
    internal var testSessionEntries: [WindowEntry]? {
        session?.entries
    }

    /// Test seam — exposes the cached space context from the active session.
    internal var testSessionSpaceID: Int? {
        session?.spaceContext.spaceID
    }

    /// Test seam — exposes the selected window id from the active session.
    internal var testSessionSelectedWindowID: Int? {
        session?.selectedWindowID
    }

    init(
        settings: SettingsRepository,
        registry: SpaceRegistry,
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil
    ) {
        self.registry = registry
        self.cgsBridge = cgsBridge
        self.settings = settings
        self.shortcutProvider = shortcutProvider ?? {
            SpaceSwitcherShortcut.parse(settings.windowSwitcherShortcutText)
                ?? SpaceSwitcherShortcut.parse("command+`")
                ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
        }
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.error("window-switcher failed=event-tap-unavailable")
            return
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        dismissPanel()
        panelPair = nil
        session = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    internal func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event: event)
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let eventFlags = event.flags
        let configuredShortcut = session?.shortcut ?? shortcutProvider()

        guard keycode == configuredShortcut.keyCode else {
            if session != nil {
                DispatchQueue.main.async { [weak self] in self?.cancelSession() }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard eventFlags.contains(configuredShortcut.modifiers) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldGoBackward = shouldMoveBackward(event: event, shortcut: configuredShortcut)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.ensureSession(using: configuredShortcut)
            self.moveSelection(offset: shouldGoBackward ? -1 : 1)
            self.showPanel()
        }
        return nil
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let activeModifiers = modifierFlags(from: event.flags)
        guard let activeSession = session,
              activeModifiers.intersection(activeSession.shortcut.modifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let didChange = activeSession.didChangeSelection
        let selectedID = activeSession.selectedWindowID
        let cachedEntries = activeSession.entries
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if didChange,
               let selectedID,
               let entry = cachedEntries.first(where: { $0.windowID == selectedID }) {
                self.commitSelection(entry)
            } else {
                self.dismissPanel()
                self.session = nil
            }
        }
        return nil
    }

    private func ensureSession(using shortcut: SpaceSwitcherShortcut) {
        if session == nil {
            guard let context = currentSpaceContext() else { return }
            let entries = selectedWindowEntries(in: context)
            session = Session(
                startingWindowID: entries.first?.windowID,
                selectedWindowID: entries.first?.windowID,
                shortcut: shortcut,
                entries: entries,
                spaceContext: context
            )
        }
    }

    private func shouldMoveBackward(event: CGEvent, shortcut: SpaceSwitcherShortcut) -> Bool {
        guard !shortcut.modifiers.contains(.maskShift) else { return false }
        return modifierFlags(from: event.flags) == shortcut.modifiers.union(.maskShift)
    }

    private func modifierFlags(from flags: CGEventFlags) -> CGEventFlags {
        var active = CGEventFlags()
        for flag in [CGEventFlags.maskShift, .maskControl, .maskAlternate, .maskCommand] where flags.contains(flag) {
            active.insert(flag)
        }
        return active
    }

    private func moveSelection(offset: Int) {
        guard var session else { return }
        let entries = session.entries
        guard !entries.isEmpty else { return }
        let ids = entries.map(\.windowID)
        let currentSelection = session.selectedWindowID ?? session.startingWindowID ?? ids.first
        let nextSelection = offset > 0
            ? nextWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
            : previousWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
        session.selectedWindowID = nextSelection
        self.session = session
    }

    private func nextWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.first
        }
        return orderedWindowIDs[(index + 1) % orderedWindowIDs.count]
    }

    private func previousWindowID(currentWindowID: Int?, orderedWindowIDs: [Int]) -> Int? {
        guard !orderedWindowIDs.isEmpty else { return nil }
        guard let currentWindowID, let index = orderedWindowIDs.firstIndex(of: currentWindowID) else {
            return orderedWindowIDs.last
        }
        return orderedWindowIDs[(index - 1 + orderedWindowIDs.count) % orderedWindowIDs.count]
    }

    private func commitSelection(_ entry: WindowEntry) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissPanel()
            self.session = nil
            self.focusWindow(entry: entry)
        }
    }

    internal func cancelSession() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissPanel()
            self.session = nil
        }
    }

    private func showPanel() {
        let snapshot = buildSnapshot()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.ensurePanel(for: snapshot)
            self.updatePanel(with: snapshot)
            self.panelPair?.window.orderFrontRegardless()
            self.panelPair?.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func dismissPanel() {
        panelPair?.window.orderOut(nil)
    }

    private func ensurePanel(for snapshot: WindowSwitcherSnapshot) {
        guard panelPair == nil else { return }

        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hosting = NSHostingController(
            rootView: WindowSwitcherView(
                snapshot: snapshot,
                onSelect: { [weak self] entry in
                    self?.commitSelection(entry)
                }
            )
        )
        window.contentViewController = hosting
        window.ignoresMouseEvents = false

        panelPair = (window, hosting)
        resizePanel(for: snapshot)
    }

    private func updatePanel(with snapshot: WindowSwitcherSnapshot) {
        guard let panelPair else { return }
        panelPair.hosting.rootView = WindowSwitcherView(
            snapshot: snapshot,
            onSelect: { [weak self] entry in
                self?.commitSelection(entry)
            }
        )
        resizePanel(for: snapshot)
    }

    private func resizePanel(for snapshot: WindowSwitcherSnapshot) {
        guard let panelPair else { return }
        let width: CGFloat = 560
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let height = Self.panelHeight(itemCount: snapshot.items.count, screenHeight: screenFrame.height)
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }

    internal static func panelHeight(itemCount: Int, screenHeight: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 40
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let emptyBodyHeight: CGFloat = 56
        let bodyHeight = itemCount == 0
            ? emptyBodyHeight
            : CGFloat(itemCount) * rowHeight + listPadding
        let minimumHeight = headerHeight + min(emptyBodyHeight, rowHeight + listPadding)
        let maxHeight = max(screenHeight - 80, minimumHeight)
        return min(headerHeight + bodyHeight, maxHeight)
    }

    private func buildSnapshot() -> WindowSwitcherSnapshot {
        let entries: [WindowEntry]
        let selectedID: Int?
        if let session {
            entries = session.entries
            selectedID = session.selectedWindowID ?? entries.first?.windowID
        } else {
            // No active session — fall back to a fresh fetch so the initial
            // panel still has data to show.
            guard let context = currentSpaceContext() else {
                return WindowSwitcherSnapshot(
                    items: [],
                    title: "Window Switcher",
                    emptyMessage: "No windows on this Space"
                )
            }
            entries = selectedWindowEntries(in: context)
            selectedID = entries.first?.windowID
        }
        let items = entries.map { entry in
            WindowSwitcherItem(
                id: entry.windowID,
                icon: entry.icon,
                title: displayTitle(for: entry),
                entry: entry,
                isSelected: entry.windowID == selectedID
            )
        }
        return WindowSwitcherSnapshot(
            items: items,
            title: "Window Switcher",
            emptyMessage: "No windows on this Space"
        )
    }

    private func selectedWindowEntries(in context: SpaceContext) -> [WindowEntry] {
        guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
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
            let application = NSRunningApplication(processIdentifier: pid)
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
                icon: icon(for: application)
            )
        }
    }

    private func currentSpaceContext() -> SpaceContext? {
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

        return SpaceContext(spaceID: activeSpaceID, desktopNumber: desktopNumber)
    }

    private func displayTitle(for entry: WindowEntry) -> String {
        WindowSwitcherTitleFormat.displayTitle(
            appName: entry.appName,
            windowTitle: entry.windowTitle,
            format: settings.windowSwitcherTitleFormat
        )
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

        let titles = accessibilityWindowTitles(for: pid)
        cache[pid] = titles
        return titles[windowNumber]
    }

    private func accessibilityWindowTitles(for pid: pid_t) -> [Int: String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return [:]
        }

        var titles: [Int: String] = [:]
        for window in windows {
            guard let number = accessibilityWindowNumber(for: window),
                  let title = accessibilityWindowTitle(for: window) else {
                continue
            }
            titles[number] = title
        }
        return titles
    }

    private func accessibilityWindowNumber(for window: AXUIElement) -> Int? {
        var numberRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberRef) == .success,
              let number = numberRef as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func accessibilityWindowTitle(for window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func icon(for application: NSRunningApplication?) -> NSImage {
        if let bundleURL = application?.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }

        let icon = NSWorkspace.shared.icon(for: UTType.application)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    private func focusWindow(entry: WindowEntry) {
        let entry = entry
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            guard let app = NSRunningApplication(processIdentifier: entry.pid) else {
                return
            }

            app.unhide()
            let activated = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            if !activated || !app.isActive {
                self.raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isActive else { return }
                    app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    self.raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
                }
                return
            }

            self.raiseWindow(pid: entry.pid, title: entry.windowTitle ?? entry.appName)
        }
    }

    private func raiseWindow(pid: pid_t, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return
        }

        let target = windows.first { window in
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let windowTitle = titleRef as? String else {
                return false
            }
            return windowTitle == title
        } ?? windows.first!

        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    internal static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<WindowSwitcherController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(event: event)
    }
}
