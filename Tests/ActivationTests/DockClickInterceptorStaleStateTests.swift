import XCTest
import CoreGraphics
import AppKit
@testable import Activation

final class DockClickInterceptorStaleStateTests: XCTestCase {
    private let dockDownPoint = CGPoint(x: 10, y: 10)
    private let dockUpPoint = CGPoint(x: 20, y: 20)
    private let dummyProxy: CGEventTapProxy = OpaquePointer(bitPattern: 0x1)!

    private func makeInterceptor(
        shouldIntercept: @escaping (String, Bool) -> Bool = { _, _ in true },
        handler: @escaping (String, Bool) -> Bool = { _, _ in true }
    ) -> DockClickInterceptor {
        let settings = MockSettingsRepository()
        return DockClickInterceptor(
            settings: settings,
            shouldIntercept: shouldIntercept,
            handler: handler
        )
    }

    private func makeMouseEvent(_ type: CGEventType, at point: CGPoint) -> CGEvent {
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
            fatalError("unsupported mouse type for tests")
        }
        return CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: point,
            mouseButton: button
        )!
    }

    /// Control: clicking the same item on down and up must call the handler
    /// with that item's bundle ID.
    func testSameItemClick_callsHandler() {
        var handlerCalls: [(String, Bool)] = []
        let interceptor = makeInterceptor(
            handler: { bundleID, option in
                handlerCalls.append((bundleID, option))
                return true
            }
        )
        interceptor.testDockBundleIDResolver = { _ in "com.example.App" }

        let down = makeMouseEvent(.leftMouseDown, at: dockDownPoint)
        let up = makeMouseEvent(.leftMouseUp, at: dockUpPoint)
        _ = interceptor.handle(proxy: dummyProxy, event: down)
        let result = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertEqual(handlerCalls.count, 1)
        XCTAssertEqual(handlerCalls.first?.0, "com.example.App")
        XCTAssertEqual(handlerCalls.first?.1, false)
        XCTAssertNil(result, "consumed event should return nil")
        XCTAssertNil(interceptor.testPendingDockClick, "pending state must be cleared")
    }

    /// C15 fix: dragging from item A to item B between mouse-down and
    /// mouse-up must NOT activate the pending item. The event is passed
    /// through so macOS can deliver a fresh click to item B.
    func testDragBetweenItems_doesNotActivatePending() {
        var handlerCalls: [(String, Bool)] = []
        let interceptor = makeInterceptor(
            handler: { bundleID, option in
                handlerCalls.append((bundleID, option))
                return true
            }
        )
        interceptor.testDockBundleIDResolver = { point in
            if point.x < 15 { return "com.example.A" }
            return "com.example.B"
        }

        let down = makeMouseEvent(.leftMouseDown, at: CGPoint(x: 10, y: 10))
        let up = makeMouseEvent(.leftMouseUp, at: CGPoint(x: 20, y: 20))
        _ = interceptor.handle(proxy: dummyProxy, event: down)
        let result = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertEqual(handlerCalls.count, 0, "handler must not be called when items differ")
        XCTAssertNotNil(result, "event must be passed through (not consumed)")
        XCTAssertNil(interceptor.testPendingDockClick)
    }

    /// Edge case: mouse-up outside the Dock (no current bundle ID) preserves
    /// the prior behavior of activating the pending click. The C15 fix
    /// must not regress this case.
    func testMouseUpOffDock_stillActivatesPending() {
        var handlerCalls: [(String, Bool)] = []
        let interceptor = makeInterceptor(
            handler: { bundleID, option in
                handlerCalls.append((bundleID, option))
                return true
            }
        )
        interceptor.testDockBundleIDResolver = { point in
            point.y < 5 ? nil : "com.example.A"
        }

        let down = makeMouseEvent(.leftMouseDown, at: CGPoint(x: 10, y: 10))
        let up = makeMouseEvent(.leftMouseUp, at: CGPoint(x: 20, y: 1))
        _ = interceptor.handle(proxy: dummyProxy, event: down)
        let result = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertEqual(handlerCalls.count, 1)
        XCTAssertEqual(handlerCalls.first?.0, "com.example.A")
        XCTAssertNil(result)
        XCTAssertNil(interceptor.testPendingDockClick)
    }

    /// Mouse-up with no prior mouse-down on a Dock item still resolves
    /// to that item's bundle ID (preserves prior behavior).
    func testMouseUpWithoutPending_resolvesToCurrent() {
        var handlerCalls: [(String, Bool)] = []
        let interceptor = makeInterceptor(
            handler: { bundleID, option in
                handlerCalls.append((bundleID, option))
                return true
            }
        )
        interceptor.testDockBundleIDResolver = { _ in "com.example.A" }

        let up = makeMouseEvent(.leftMouseUp, at: dockUpPoint)
        let result = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertEqual(handlerCalls.count, 1)
        XCTAssertEqual(handlerCalls.first?.0, "com.example.A")
        XCTAssertNil(result)
        XCTAssertNil(interceptor.testPendingDockClick)
    }

    /// M6: pending click must be cleared on every leftMouseUp path,
    /// even if the event is passed through (different item).
    func testPendingClickIsClearedOnMismatch() {
        let interceptor = makeInterceptor()
        interceptor.testPendingDockClick = .init(bundleID: "com.example.A", optionHeld: false)
        interceptor.testDockBundleIDResolver = { _ in "com.example.B" }

        let up = makeMouseEvent(.leftMouseUp, at: dockUpPoint)
        _ = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertNil(interceptor.testPendingDockClick)
    }

    /// When the handler returns false (didn't handle the event), the
    /// event must be passed through unchanged.
    func testHandlerReturnsFalse_passesEventThrough() {
        let interceptor = makeInterceptor(handler: { _, _ in false })
        interceptor.testDockBundleIDResolver = { _ in "com.example.A" }

        let down = makeMouseEvent(.leftMouseDown, at: dockDownPoint)
        let up = makeMouseEvent(.leftMouseUp, at: dockUpPoint)
        _ = interceptor.handle(proxy: dummyProxy, event: down)
        let result = interceptor.handle(proxy: dummyProxy, event: up)

        XCTAssertNotNil(result, "event must be passed through when handler returns false")
        XCTAssertNil(interceptor.testPendingDockClick)
    }
}
