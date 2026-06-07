import CoreGraphics
import Core
import Foundation

protocol SwitcherEventSessionHandling: AnyObject {
    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut
    func switcherHasActiveSession() -> Bool
    func switcherSessionModifiers() -> CGEventFlags?
    func switcherEnsureSessionAndMoveSelection(backward: Bool)
    func switcherCommitOrDismissActiveSession()
    func switcherCancelActiveSession()
}

final class SwitcherEventControllerSupport {
    typealias EventTapFactory = (CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
    typealias RunLoopSourceFactory = (CFMachPort) -> CFRunLoopSource?
    typealias TapEnableHandler = (CFMachPort?, Bool) -> Void
    typealias RunLoopSourceHandler = (CFRunLoopSource) -> Void

    private weak var handler: (any SwitcherEventSessionHandling)?
    private let eventTapUnavailableLog: String
    private let eventTapFactory: EventTapFactory
    private let runLoopSourceFactory: RunLoopSourceFactory
    private let tapEnableHandler: TapEnableHandler
    private let addRunLoopSource: RunLoopSourceHandler
    private let removeRunLoopSource: RunLoopSourceHandler

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        handler: any SwitcherEventSessionHandling,
        eventTapUnavailableLog: String,
        eventTapFactory: @escaping EventTapFactory = SwitcherEventControllerSupport.liveEventTapFactory,
        runLoopSourceFactory: @escaping RunLoopSourceFactory = SwitcherEventControllerSupport.liveRunLoopSourceFactory,
        tapEnableHandler: @escaping TapEnableHandler = SwitcherEventControllerSupport.liveTapEnableHandler,
        addRunLoopSource: @escaping RunLoopSourceHandler = SwitcherEventControllerSupport.liveAddRunLoopSource,
        removeRunLoopSource: @escaping RunLoopSourceHandler = SwitcherEventControllerSupport.liveRemoveRunLoopSource
    ) {
        self.handler = handler
        self.eventTapUnavailableLog = eventTapUnavailableLog
        self.eventTapFactory = eventTapFactory
        self.runLoopSourceFactory = runLoopSourceFactory
        self.tapEnableHandler = tapEnableHandler
        self.addRunLoopSource = addRunLoopSource
        self.removeRunLoopSource = removeRunLoopSource
    }

    func start() {
        guard eventTap == nil else { return }

        guard let eventTap = eventTapFactory(Self.eventTapCallback, Unmanaged.passUnretained(self).toOpaque()) else {
            Logger.shared.error(eventTapUnavailableLog)
            return
        }

        self.eventTap = eventTap
        let source = runLoopSourceFactory(eventTap)
        runLoopSource = source
        if let source {
            addRunLoopSource(source)
        }
        tapEnableHandler(eventTap, true)
    }

    func stop() {
        if let eventTap {
            tapEnableHandler(eventTap, false)
        }
        if let runLoopSource {
            removeRunLoopSource(runLoopSource)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisabledEvent()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event: event)
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    internal func handleTapDisabledEvent(forceReenable: Bool = false) {
        if forceReenable || eventTap != nil {
            tapEnableHandler(eventTap, true)
        }
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let handler else { return Unmanaged.passUnretained(event) }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let eventFlags = event.flags
        let configuredShortcut = handler.switcherConfiguredShortcut()

        guard keycode == configuredShortcut.keyCode else {
            if handler.switcherHasActiveSession() {
                DispatchQueue.main.async { [weak handler] in
                    handler?.switcherCancelActiveSession()
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard eventFlags.contains(configuredShortcut.modifiers) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldGoBackward = shouldMoveBackward(event: event, shortcut: configuredShortcut)
        DispatchQueue.main.async { [weak handler] in
            handler?.switcherEnsureSessionAndMoveSelection(backward: shouldGoBackward)
        }
        return nil
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let handler,
              let sessionModifiers = handler.switcherSessionModifiers() else {
            return Unmanaged.passUnretained(event)
        }

        let activeModifiers = modifierFlags(from: event.flags)
        guard activeModifiers.intersection(sessionModifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak handler] in
            handler?.switcherCommitOrDismissActiveSession()
        }
        return nil
    }

    internal func modifierFlags(from flags: CGEventFlags) -> CGEventFlags {
        var active = CGEventFlags()
        for flag in [CGEventFlags.maskShift, .maskControl, .maskAlternate, .maskCommand] where flags.contains(flag) {
            active.insert(flag)
        }
        return active
    }

    private func shouldMoveBackward(event: CGEvent, shortcut: SpaceSwitcherShortcut) -> Bool {
        guard !shortcut.modifiers.contains(.maskShift) else { return false }
        return modifierFlags(from: event.flags) == shortcut.modifiers.union(.maskShift)
    }

    internal static let eventTapCallback: CGEventTapCallBack = { _, _, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let support = Unmanaged<SwitcherEventControllerSupport>.fromOpaque(userInfo).takeUnretainedValue()
        return support.handle(event: event)
    }

    private static func liveEventTapFactory(
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        )
    }

    private static func liveRunLoopSourceFactory(eventTap: CFMachPort) -> CFRunLoopSource? {
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    }

    private static func liveTapEnableHandler(eventTap: CFMachPort?, enabled: Bool) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: enabled)
    }

    private static func liveAddRunLoopSource(source: CFRunLoopSource) {
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private static func liveRemoveRunLoopSource(source: CFRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
