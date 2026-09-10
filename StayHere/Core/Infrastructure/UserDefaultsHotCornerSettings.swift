import Foundation

public final class UserDefaultsHotCornerSettings: SettingsBackingStore, HotCornerSettings {
    private enum Key {
        static let hotCornerTopLeftAction = "hotCorner.topLeft.action"
        static let hotCornerTopRightAction = "hotCorner.topRight.action"
        static let hotCornerBottomLeftAction = "hotCorner.bottomLeft.action"
        static let hotCornerBottomRightAction = "hotCorner.bottomRight.action"
    }

    private enum Defaults {
        static let hotCornerAction: HotCornerAction = .none
    }

    public var hotCornerTopLeftAction: HotCornerAction {
        get { defaults[setting: Key.hotCornerTopLeftAction, default: Defaults.hotCornerAction] }
        set { defaults[setting: Key.hotCornerTopLeftAction, default: Defaults.hotCornerAction] = newValue }
    }

    public var hotCornerTopRightAction: HotCornerAction {
        get { defaults[setting: Key.hotCornerTopRightAction, default: Defaults.hotCornerAction] }
        set { defaults[setting: Key.hotCornerTopRightAction, default: Defaults.hotCornerAction] = newValue }
    }

    public var hotCornerBottomLeftAction: HotCornerAction {
        get { defaults[setting: Key.hotCornerBottomLeftAction, default: Defaults.hotCornerAction] }
        set { defaults[setting: Key.hotCornerBottomLeftAction, default: Defaults.hotCornerAction] = newValue }
    }

    public var hotCornerBottomRightAction: HotCornerAction {
        get { defaults[setting: Key.hotCornerBottomRightAction, default: Defaults.hotCornerAction] }
        set { defaults[setting: Key.hotCornerBottomRightAction, default: Defaults.hotCornerAction] = newValue }
    }
}
