import AppKit
import Core

@MainActor
final class HotCornerController {
    typealias MouseLocationProvider = () -> CGPoint
    typealias ScreenFramesProvider = () -> [CGRect]
    typealias ActionHandler = (HotCornerAction) -> Void

    private enum Constants {
        static let pollInterval: TimeInterval = 0.2
        static let activationDistance: CGFloat = 3
    }

    private let settings: SettingsRepository
    private let mouseLocationProvider: MouseLocationProvider
    private let screenFramesProvider: ScreenFramesProvider
    private let actionHandler: ActionHandler

    private var pollTimer: Timer?
    private var lastHoveredCorner: HotCorner?

    init(
        settings: SettingsRepository,
        mouseLocationProvider: @escaping MouseLocationProvider = { NSEvent.mouseLocation },
        screenFramesProvider: @escaping ScreenFramesProvider = { NSScreen.screens.map(\.frame) },
        actionHandler: @escaping ActionHandler
    ) {
        self.settings = settings
        self.mouseLocationProvider = mouseLocationProvider
        self.screenFramesProvider = screenFramesProvider
        self.actionHandler = actionHandler
    }

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastHoveredCorner = nil
    }

    func hasAssignedCorners() -> Bool {
        HotCorner.allCases.contains { action(for: $0) != .none }
    }

    func poll() {
        let currentCorner = Self.detectCorner(
            at: mouseLocationProvider(),
            in: screenFramesProvider(),
            activationDistance: Constants.activationDistance
        )
        defer { lastHoveredCorner = currentCorner }
        guard currentCorner != lastHoveredCorner,
              let currentCorner else {
            return
        }

        let configuredAction = action(for: currentCorner)
        guard configuredAction != .none else { return }
        actionHandler(configuredAction)
    }

    private func action(for corner: HotCorner) -> HotCornerAction {
        switch corner {
        case .topLeft:
            return settings.hotCornerTopLeftAction
        case .topRight:
            return settings.hotCornerTopRightAction
        case .bottomLeft:
            return settings.hotCornerBottomLeftAction
        case .bottomRight:
            return settings.hotCornerBottomRightAction
        }
    }

    static func detectCorner(
        at point: CGPoint,
        in screenFrames: [CGRect],
        activationDistance: CGFloat
    ) -> HotCorner? {
        for frame in screenFrames {
            if abs(point.x - frame.minX) <= activationDistance &&
                abs(point.y - frame.maxY) <= activationDistance {
                return .topLeft
            }
            if abs(point.x - frame.maxX) <= activationDistance &&
                abs(point.y - frame.maxY) <= activationDistance {
                return .topRight
            }
            if abs(point.x - frame.minX) <= activationDistance &&
                abs(point.y - frame.minY) <= activationDistance {
                return .bottomLeft
            }
            if abs(point.x - frame.maxX) <= activationDistance &&
                abs(point.y - frame.minY) <= activationDistance {
                return .bottomRight
            }
        }

        return nil
    }
}
