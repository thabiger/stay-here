import CoreGraphics
import Core
import Foundation

final class AppEventTapProxy: EventTapProxying {
    typealias EventTapFactory = (CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
    typealias RunLoopSourceFactory = (CFMachPort) -> CFRunLoopSource?
    typealias TapEnableHandler = (CFMachPort?, Bool) -> Void
    typealias RunLoopSourceHandler = (CFRunLoopSource) -> Void

    private let eventTapFactory: EventTapFactory
    private let runLoopSourceFactory: RunLoopSourceFactory
    private let tapEnableHandler: TapEnableHandler
    private let addRunLoopSource: RunLoopSourceHandler
    private let removeRunLoopSource: RunLoopSourceHandler
    private let logger: any Logging

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var clients: [any CGEventTapClient] = []

    init(
        eventTapFactory: @escaping EventTapFactory = AppEventTapProxy.liveEventTapFactory,
        runLoopSourceFactory: @escaping RunLoopSourceFactory = AppEventTapProxy.liveRunLoopSourceFactory,
        tapEnableHandler: @escaping TapEnableHandler = AppEventTapProxy.liveTapEnableHandler,
        addRunLoopSource: @escaping RunLoopSourceHandler = AppEventTapProxy.liveAddRunLoopSource,
        removeRunLoopSource: @escaping RunLoopSourceHandler = AppEventTapProxy.liveRemoveRunLoopSource,
        logger: any Logging
    ) {
        self.eventTapFactory = eventTapFactory
        self.runLoopSourceFactory = runLoopSourceFactory
        self.tapEnableHandler = tapEnableHandler
        self.addRunLoopSource = addRunLoopSource
        self.removeRunLoopSource = removeRunLoopSource
        self.logger = logger
    }

    deinit {
        tearDownTap()
    }

    func register(_ client: any CGEventTapClient) {
        guard !clients.contains(where: { $0 === client }) else { return }
        clients.append(client)
        ensureTapRunning()
    }

    func unregister(_ client: any CGEventTapClient) {
        clients.removeAll { $0 === client }
        if clients.isEmpty {
            tearDownTap()
        }
    }

    func removeAllClients() {
        clients.removeAll()
        tearDownTap()
    }

    private func ensureTapRunning() {
        guard eventTap == nil else { return }

        guard let tap = eventTapFactory(Self.eventTapCallback, Unmanaged.passUnretained(self).toOpaque()) else {
            logger.error("app-wide event tap unavailable")
            return
        }

        eventTap = tap
        let source = runLoopSourceFactory(tap)
        runLoopSource = source
        if let source {
            addRunLoopSource(source)
        }
        tapEnableHandler(tap, true)
    }

    private func tearDownTap() {
        if let eventTap {
            tapEnableHandler(eventTap, false)
        }
        if let runLoopSource {
            removeRunLoopSource(runLoopSource)
        }
        eventTap = nil
        runLoopSource = nil
    }

    internal func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapEnableHandler(eventTap, true)
            return Unmanaged.passUnretained(event)
        case .keyDown, .flagsChanged:
            return dispatchKeyboardEvent(proxy: proxy, event: event)
        case .leftMouseDown, .leftMouseUp:
            return dispatchMouseEvent(proxy: proxy, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func dispatchKeyboardEvent(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyboardClients = clients.filter { $0.handlesKeyboardEvents }
        let activeClients = keyboardClients.filter { $0.hasActiveSession }
        let targets = activeClients.isEmpty ? keyboardClients : activeClients

        for client in targets {
            if client.handle(proxy: proxy, event: event) != nil {
                continue
            } else {
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func dispatchMouseEvent(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let mouseClients = clients.filter { $0.handlesMouseEvents }
        for client in mouseClients {
            if client.handle(proxy: proxy, event: event) != nil {
                continue
            } else {
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tapProxy = Unmanaged<AppEventTapProxy>.fromOpaque(userInfo).takeUnretainedValue()
        return tapProxy.handle(proxy: proxy, type: type, event: event)
    }

    private static func liveEventTapFactory(
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        guard !RuntimeEnvironment.isAutomationSession else { return nil }

        let keyDownMask = 1 << CGEventType.keyDown.rawValue
        let flagsChangedMask = 1 << CGEventType.flagsChanged.rawValue
        let leftMouseDownMask = 1 << CGEventType.leftMouseDown.rawValue
        let leftMouseUpMask = 1 << CGEventType.leftMouseUp.rawValue
        let tapDisabledByTimeoutMask = 1 << CGEventType.tapDisabledByTimeout.rawValue
        let tapDisabledByUserInputMask = 1 << CGEventType.tapDisabledByUserInput.rawValue
        let combinedMask = keyDownMask
            | flagsChangedMask
            | leftMouseDownMask
            | leftMouseUpMask
            | tapDisabledByTimeoutMask
            | tapDisabledByUserInputMask
        let mask = CGEventMask(combinedMask)
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
