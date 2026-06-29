import XCTest
import CoreGraphics
import Core
@testable import StayHereApp

@MainActor
final class HotCornerControllerTests: XCTestCase {
    private func makeSettings() -> UserDefaultsSettingsRepository {
        let suiteName = "HotCornerControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsSettingsRepository(defaults: defaults)
    }

    func testPollTriggersAssignedActionOncePerCornerEntry() {
        let settings = makeSettings()
        settings.hotCornerTopLeftAction = .spaceSwitcher
        var mouseLocation = CGPoint(x: 0, y: 100)
        var triggeredActions: [HotCornerAction] = []
        let controller = HotCornerController(
            settings: settings,
            mouseLocationProvider: { mouseLocation },
            screenFramesProvider: { [CGRect(x: 0, y: 0, width: 100, height: 100)] },
            actionHandler: { triggeredActions.append($0) }
        )

        controller.start()

        mouseLocation = CGPoint(x: 0, y: 100)
        controller.poll()
        controller.poll()
        mouseLocation = CGPoint(x: 10, y: 90)
        controller.poll()
        mouseLocation = CGPoint(x: 0, y: 100)
        controller.poll()

        controller.stop()

        XCTAssertEqual(triggeredActions, [.spaceSwitcher, .spaceSwitcher])
    }

    func testPollIgnoresUnassignedCorner() {
        let settings = makeSettings()
        var triggeredActions: [HotCornerAction] = []
        let controller = HotCornerController(
            settings: settings,
            mouseLocationProvider: { CGPoint(x: 100, y: 100) },
            screenFramesProvider: { [CGRect(x: 0, y: 0, width: 100, height: 100)] },
            actionHandler: { triggeredActions.append($0) }
        )

        controller.poll()

        XCTAssertTrue(triggeredActions.isEmpty)
    }

    func testHasAssignedCornersReflectsCurrentSettings() {
        let settings = makeSettings()
        let controller = HotCornerController(
            settings: settings,
            actionHandler: { _ in }
        )

        XCTAssertFalse(controller.hasAssignedCorners())

        settings.hotCornerBottomLeftAction = .windowSwitcher

        XCTAssertTrue(controller.hasAssignedCorners())
    }

    func testDetectCornerSupportsEveryScreenCorner() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 100)

        XCTAssertEqual(
            HotCornerController.detectCorner(
                at: CGPoint(x: frame.minX, y: frame.maxY),
                in: [frame],
                activationDistance: 3
            ),
            .topLeft
        )
        XCTAssertEqual(
            HotCornerController.detectCorner(
                at: CGPoint(x: frame.maxX, y: frame.maxY),
                in: [frame],
                activationDistance: 3
            ),
            .topRight
        )
        XCTAssertEqual(
            HotCornerController.detectCorner(
                at: CGPoint(x: frame.minX, y: frame.minY),
                in: [frame],
                activationDistance: 3
            ),
            .bottomLeft
        )
        XCTAssertEqual(
            HotCornerController.detectCorner(
                at: CGPoint(x: frame.maxX, y: frame.minY),
                in: [frame],
                activationDistance: 3
            ),
            .bottomRight
        )
    }
}
