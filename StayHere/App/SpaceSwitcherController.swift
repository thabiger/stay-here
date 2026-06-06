import AppKit
import CoreGraphics
import Core
import SwiftUI

final class SpaceSwitcherController {
    private struct Session {
        let startingSpaceID: Int?
        var selectedSpaceID: Int?
        let shortcut: SpaceSwitcherShortcut

        var didChangeSelection: Bool {
            selectedSpaceID != nil && selectedSpaceID != startingSpaceID
        }
    }

    private let registry: SpaceRegistry
    private let switchToSpace: (Int) -> Void
    private let shortcutProvider: () -> SpaceSwitcherShortcut

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session: Session?
    private var panelPair: (window: NSPanel, hosting: NSHostingController<SpaceSwitcherView>)?

    init(
        registry: SpaceRegistry,
        switchToSpace: @escaping (Int) -> Void,
        shortcutProvider: @escaping () -> SpaceSwitcherShortcut = { SpaceSwitcherSettings.shared.shortcut }
    ) {
        self.registry = registry
        self.switchToSpace = switchToSpace
        self.shortcutProvider = shortcutProvider
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
            Logger.shared.error("space-switcher failed=event-tap-unavailable")
            return
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        dismissPanel()
        session = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
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

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let configuredShortcut = session?.shortcut ?? shortcutProvider()

        guard event.getIntegerValueField(.keyboardEventKeycode) == configuredShortcut.keyCode else {
            if session != nil {
                cancelSession()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard event.flags.contains(configuredShortcut.modifiers) else {
            return Unmanaged.passUnretained(event)
        }

        ensureSession(using: configuredShortcut)

        if shouldMoveBackward(event: event, shortcut: configuredShortcut) {
            moveSelection(offset: -1)
        } else {
            moveSelection(offset: 1)
        }
        showPanel()
        return nil
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let session, modifierFlags(from: event.flags).intersection(session.shortcut.modifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        if session.didChangeSelection, let selectedID = session.selectedSpaceID {
            commitSelection(selectedID)
        } else {
            dismissPanel()
        }
        self.session = nil
        return nil
    }

    private func ensureSession(using shortcut: SpaceSwitcherShortcut) {
        if session == nil {
            session = Session(
                startingSpaceID: registry.activeSpaceID,
                selectedSpaceID: registry.activeSpaceID,
                shortcut: shortcut
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
        let ordered = registry.orderedSpaceIDs()
        let currentSelection = session.selectedSpaceID ?? session.startingSpaceID
        let nextSelection = offset > 0
            ? SpaceCycling.nextSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
            : SpaceCycling.previousSpaceID(currentSpaceID: currentSelection, orderedSpaceIDs: ordered)
        session.selectedSpaceID = nextSelection
        self.session = session
    }

    private func commitSelection(_ spaceID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissPanel()
            self.session = nil
            self.switchToSpace(spaceID)
        }
    }

    private func cancelSession() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissPanel()
        }
        session = nil
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

    private func ensurePanel(for snapshot: SpaceSwitcherSnapshot) {
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
            rootView: SpaceSwitcherView(
                snapshot: snapshot,
                onSelect: { [weak self] spaceID in
                    self?.commitSelection(spaceID)
                }
            )
        )
        window.contentViewController = hosting
        window.ignoresMouseEvents = false

        panelPair = (window, hosting)
        resizePanel(for: snapshot)
    }

    private func updatePanel(with snapshot: SpaceSwitcherSnapshot) {
        guard let panelPair else { return }
        panelPair.hosting.rootView = SpaceSwitcherView(
            snapshot: snapshot,
            onSelect: { [weak self] spaceID in
                self?.commitSelection(spaceID)
            }
        )
        resizePanel(for: snapshot)
    }

    private func resizePanel(for snapshot: SpaceSwitcherSnapshot) {
        guard let panelPair else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let width = min(max(screenFrame.width * 0.32, 420), 560)
        let rowHeight: CGFloat = 38
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let visibleRows = max(snapshot.items.count, 1)
        let desiredHeight = headerHeight + CGFloat(visibleRows) * rowHeight + listPadding
        let height = min(desiredHeight, max(screenFrame.height - 80, headerHeight + rowHeight + listPadding))
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }

    private func buildSnapshot() -> SpaceSwitcherSnapshot {
        let orderedIDs = registry.orderedSpaceIDs()
        let selectedID = session?.selectedSpaceID ?? registry.activeSpaceID
        let items = orderedIDs.map { id in
            SpaceSwitcherItem(
                id: id,
                title: "\(registry.namespaceLabel(for: id))  \(registry.name(for: id))",
                isSelected: id == selectedID,
                isCurrent: id == registry.activeSpaceID
            )
        }
        return SpaceSwitcherSnapshot(items: items, title: "Space Switcher")
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<SpaceSwitcherController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(event: event)
    }
}
