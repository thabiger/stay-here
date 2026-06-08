# Changelog

## unreleased
- Replaced the six `public static let shared` settings classes (`AppearanceSettings`, `DiagnosticsSettings`, `SpaceSwitcherSettings`, `WindowSwitcherSettings`, `HUDSettings`, `ActivationSettings`) with a single `SettingsRepository` protocol injected into all consumers. Added a `UserDefaultsSettingsRepository` implementation and a `MockSettingsRepository` for tests. Removed the hidden coupling between `Logger` and `DiagnosticsSettings.shared` by passing the repository into the `Logger` initializer. Consolidated the duplicated shortcut-parsing tables in `SpaceSwitcherSettings` and `WindowSwitcherSettings` into a single `ShortcutKeyCodes` mapping used by `SpaceSwitcherShortcut.parse`.

## v0.1.1
- Bug fix Y

## v0.1.0
- Initial release

