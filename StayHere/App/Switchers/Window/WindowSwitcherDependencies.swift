import Core

/// Groups the overrideable dependencies of `WindowSwitcherController`.
///
/// Every field is optional: `nil` means "construct the production default
/// internally" (see `WindowSwitcherController.init`). Required configuration
/// (settings, registry, mode, windowSwitchUseCase, cgsBridge) stays as
/// explicit init parameters.
struct WindowSwitcherDependencies {
    var shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil
    var listProvider: WindowListProvider? = nil
    var recencyTracker: WindowRecencyTracker? = nil
    var listBuilder: WindowListBuilder? = nil
    var panelPresenter: WindowSwitcherPanelPresenter? = nil
}
