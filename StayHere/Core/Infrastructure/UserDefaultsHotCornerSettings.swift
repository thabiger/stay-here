import Foundation

public final class UserDefaultsHotCornerSettings: HotCornerSettings {
    private enum Key {
        static let hotCornerTopLeftAction = "hotCorner.topLeft.action"
        static let hotCornerTopRightAction = "hotCorner.topRight.action"
        static let hotCornerBottomLeftAction = "hotCorner.bottomLeft.action"
        static let hotCornerBottomRightAction = "hotCorner.bottomRight.action"
    }

    private enum Defaults {
        static let hotCornerAction: HotCornerAction = .none
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hotCornerTopLeftAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerTopLeftAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerTopLeftAction) }
    }

    public var hotCornerTopRightAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerTopRightAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerTopRightAction) }
    }

    public var hotCornerBottomLeftAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerBottomLeftAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerBottomLeftAction) }
    }

    public var hotCornerBottomRightAction: HotCornerAction {
        get { hotCornerAction(forKey: Key.hotCornerBottomRightAction) }
        set { defaults.set(newValue.rawValue, forKey: Key.hotCornerBottomRightAction) }
    }

    private func hotCornerAction(forKey key: String) -> HotCornerAction {
        if let stored = defaults.string(forKey: key),
           let action = HotCornerAction(rawValue: stored) {
            return action
        }
        return Defaults.hotCornerAction
    }
}
