import XCTest
import CoreGraphics
import Core
@testable import StayHereApp

final class AppEventTapProxyTests: XCTestCase {
    private let dummyProxy: CGEventTapProxy = OpaquePointer(bitPattern: 0x1)!

    private func makeDummyMachPort() -> CFMachPort? {
        // Create a real CFMachPort so the proxy believes a tap exists.
        // We do not actually install it on a run loop.
        return CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
    }

    private func makeProxy(
        eventTapFactory: @escaping AppEventTapProxy.EventTapFactory = { _, _ in nil }
    ) -> AppEventTapProxy {
        AppEventTapProxy(
            eventTapFactory: eventTapFactory,
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, _ in },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in },
            logger: NoOpLogger()
        )
    }

    private func makeKeyEvent(keyCode: CGKeyCode = 0, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return event
    }

    private func makeMouseEvent(type: CGEventType, point: CGPoint = .zero) -> CGEvent {
        let mouseType: CGEventType
        let button: CGMouseButton
        switch type {
        case .leftMouseDown:
            mouseType = .leftMouseDown
            button = .left
        case .leftMouseUp:
            mouseType = .leftMouseUp
            button = .left
        default:
            fatalError("unsupported mouse type")
        }
        return CGEvent(mouseEventSource: nil, mouseType: mouseType, mouseCursorPosition: point, mouseButton: button)!
    }

    func testRegisterStartsTap() {
        var factoryCalls: [(CGEventTapCallBack, UnsafeMutableRawPointer?)] = []
        let proxy = makeProxy { callback, userInfo in
            factoryCalls.append((callback, userInfo))
            return nil
        }
        let client = FakeClient()

        proxy.register(client)

        XCTAssertEqual(factoryCalls.count, 1)
    }

    func testUnregisterStopsTapWhenLastClientRemoved() {
        var enableCalls: [Bool] = []
        var removedSources = 0
        let proxy = AppEventTapProxy(
            eventTapFactory: { _, _ in self.makeDummyMachPort() },
            runLoopSourceFactory: { tap in CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in removedSources += 1 },
            logger: NoOpLogger()
        )
        let client = FakeClient()

        proxy.register(client)
        proxy.unregister(client)

        XCTAssertEqual(enableCalls.last, false)
        XCTAssertEqual(removedSources, 1)
    }

    func testTapDisabledReEnablesTap() throws {
        var enableCalls: [Bool] = []
        let proxy = AppEventTapProxy(
            eventTapFactory: { _, _ in self.makeDummyMachPort() },
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in },
            logger: NoOpLogger()
        )
        let client = FakeClient()
        proxy.register(client)
        enableCalls.removeAll()

        let disabledEvent = CGEvent(source: nil)!
        disabledEvent.type = .tapDisabledByTimeout

        // Send the timeout event; re-enable should be scheduled, not immediate
        let result = proxy.handle(
            proxy: dummyProxy,
            type: CGEventType.tapDisabledByTimeout,
            event: disabledEvent
        )

        XCTAssertNotNil(result)
        // Should NOT have re-enabled immediately
        XCTAssertEqual(enableCalls, [])

        // Wait for the async re-enable (first backoff = 1s, add generous tolerance)
        let reenableExpectation = XCTestExpectation(description: "tap re-enabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            reenableExpectation.fulfill()
        }
        wait(for: [reenableExpectation], timeout: 2.0)

        XCTAssertEqual(enableCalls, [true])
        XCTAssertTrue(client.handledEvents.isEmpty, "tap-disabled events should not be dispatched to clients")
    }

    func testTapDisabledByUserInputDoesNotReEnable() {
        var enableCalls: [Bool] = []
        let proxy = AppEventTapProxy(
            eventTapFactory: { _, _ in self.makeDummyMachPort() },
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in },
            logger: NoOpLogger()
        )
        let client = FakeClient()
        proxy.register(client)
        enableCalls.removeAll()

        let disabledEvent = CGEvent(source: nil)!
        disabledEvent.type = .tapDisabledByUserInput

        let result = proxy.handle(
            proxy: dummyProxy,
            type: CGEventType.tapDisabledByUserInput,
            event: disabledEvent
        )

        XCTAssertNotNil(result)
        // Should NOT have re-enabled
        XCTAssertEqual(enableCalls, [])

        // Wait a beat to confirm no delayed re-enable
        let noReenableExpectation = XCTestExpectation(description: "no re-enable happened")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            noReenableExpectation.fulfill()
        }
        wait(for: [noReenableExpectation], timeout: 2.0)
        XCTAssertEqual(enableCalls, [])
    }

    func testConsecutiveTimeoutsIncreaseBackoff() {
        var enableCalls: [Bool] = []
        let proxy = AppEventTapProxy(
            eventTapFactory: { _, _ in self.makeDummyMachPort() },
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in },
            logger: NoOpLogger()
        )
        let client = FakeClient()
        proxy.register(client)
        enableCalls.removeAll()

        let disabledEvent = CGEvent(source: nil)!
        disabledEvent.type = .tapDisabledByTimeout

        // First timeout — backoff = 1s
        _ = proxy.handle(proxy: dummyProxy, type: .tapDisabledByTimeout, event: disabledEvent)

        // Wait for first re-enable
        let first = XCTestExpectation(description: "first re-enable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { first.fulfill() }
        wait(for: [first], timeout: 2.0)
        XCTAssertEqual(enableCalls, [true])
        enableCalls.removeAll()

        // Second timeout — backoff should now be 2s
        _ = proxy.handle(proxy: dummyProxy, type: .tapDisabledByTimeout, event: disabledEvent)

        // Verify it does NOT re-enable within 1s (would be too early for 2s backoff)
        let tooEarly = XCTestExpectation(description: "should not re-enable too early")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            XCTAssertEqual(enableCalls, [])
            tooEarly.fulfill()
        }
        wait(for: [tooEarly], timeout: 1.0)

        // Wait for the actual re-enable
        let second = XCTestExpectation(description: "second re-enable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { second.fulfill() }
        wait(for: [second], timeout: 2.0)
        XCTAssertEqual(enableCalls, [true])
    }

    func testNormalEventResetsBackoffCounter() {
        var enableCalls: [Bool] = []
        let proxy = AppEventTapProxy(
            eventTapFactory: { _, _ in self.makeDummyMachPort() },
            runLoopSourceFactory: { _ in nil },
            tapEnableHandler: { _, enabled in enableCalls.append(enabled) },
            addRunLoopSource: { _ in },
            removeRunLoopSource: { _ in },
            logger: NoOpLogger()
        )
        let client = FakeClient()
        proxy.register(client)
        enableCalls.removeAll()

        // First timeout — backoff = 1s
        let disabledEvent = CGEvent(source: nil)!
        disabledEvent.type = .tapDisabledByTimeout
        _ = proxy.handle(proxy: dummyProxy, type: .tapDisabledByTimeout, event: disabledEvent)

        // Wait for re-enable
        let first = XCTestExpectation(description: "first re-enable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { first.fulfill() }
        wait(for: [first], timeout: 2.0)
        enableCalls.removeAll()

        // Simulate a normal key event — this should reset the counter to 0
        _ = proxy.handle(proxy: dummyProxy, type: .keyDown, event: makeKeyEvent())

        // Now another timeout — with reset counter, backoff should be 1s again, not 2s
        _ = proxy.handle(proxy: dummyProxy, type: .tapDisabledByTimeout, event: disabledEvent)

        let second = XCTestExpectation(description: "second re-enable should arrive in ~1s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { second.fulfill() }
        wait(for: [second], timeout: 2.0)
        XCTAssertEqual(enableCalls, [true])
    }

    func testKeyboardEventRoutesToActiveClientExclusively() {
        let proxy = makeProxy()
        let activeClient = FakeClient(hasActiveSession: true)
        let idleClient = FakeClient()
        proxy.register(idleClient)
        proxy.register(activeClient)

        _ = proxy.handle(proxy: dummyProxy, type: .keyDown, event: makeKeyEvent())

        XCTAssertEqual(activeClient.handledEvents.count, 1)
        XCTAssertEqual(idleClient.handledEvents.count, 0)
    }

    func testKeyboardEventRoutesInRegistrationOrderWhenNoActiveClient() {
        let proxy = makeProxy()
        let first = FakeClient()
        let second = FakeClient(consumesEvents: true)
        let third = FakeClient()
        proxy.register(first)
        proxy.register(second)
        proxy.register(third)

        let result = proxy.handle(proxy: dummyProxy, type: .keyDown, event: makeKeyEvent())

        XCTAssertEqual(first.handledEvents.count, 1)
        XCTAssertEqual(second.handledEvents.count, 1)
        XCTAssertEqual(third.handledEvents.count, 0)
        XCTAssertNil(result)
    }

    func testMouseEventRoutesToMouseHandlingClients() {
        let proxy = makeProxy()
        let keyboardClient = FakeClient(handlesKeyboardEvents: true)
        let mouseClient = FakeClient(handlesMouseEvents: true)
        proxy.register(keyboardClient)
        proxy.register(mouseClient)

        let result = proxy.handle(proxy: dummyProxy, type: .leftMouseDown, event: makeMouseEvent(type: .leftMouseDown))

        XCTAssertEqual(keyboardClient.handledEvents.count, 0)
        XCTAssertEqual(mouseClient.handledEvents.count, 1)
        XCTAssertNotNil(result)
    }

    func testConsumedEventStopsRouting() {
        let proxy = makeProxy()
        let consumer = FakeClient(consumesEvents: true)
        let later = FakeClient()
        proxy.register(consumer)
        proxy.register(later)

        let result = proxy.handle(proxy: dummyProxy, type: .keyDown, event: makeKeyEvent())

        XCTAssertEqual(consumer.handledEvents.count, 1)
        XCTAssertEqual(later.handledEvents.count, 0)
        XCTAssertNil(result)
    }
}

private final class FakeClient: CGEventTapClient {
    private let consumesEvents: Bool
    var hasActiveSession: Bool
    var handlesKeyboardEvents: Bool
    var handlesMouseEvents: Bool
    private(set) var handledEvents: [CGEvent] = []

    init(
        consumesEvents: Bool = false,
        hasActiveSession: Bool = false,
        handlesKeyboardEvents: Bool = true,
        handlesMouseEvents: Bool = false
    ) {
        self.consumesEvents = consumesEvents
        self.hasActiveSession = hasActiveSession
        self.handlesKeyboardEvents = handlesKeyboardEvents
        self.handlesMouseEvents = handlesMouseEvents
    }

    func handle(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        handledEvents.append(event)
        return consumesEvents ? nil : Unmanaged.passUnretained(event)
    }
}
