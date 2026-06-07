# Changelog

## phase-2 (unreleased)
- Added Dock click interception with configurable mode: `Replace Dock clicks`, `Disabled`, and automatic single-window app moves on normal clicks.
- Added `ActivationPolicy` and `ActivationExecutor` for launch/focus/new-window/single-window-move decisions.
- Added `WindowIndex` process window summarization used by activation decisions.
- Added activation diagnostics log lines (`activation ... decision=...`) to support phase checklist verification.
- Added Phase 2 gate document at `docs/gates/PHASE-2.md`.
- Added a configurable global space switcher picker, defaulting to `Option+Tab`, with support for custom shortcuts in Settings.
- Added a configurable window switcher picker, defaulting to `Command+Tab`, showing current-space windows with app icons.
- Added window switcher visibility options for minimized and hidden windows.
- Added a window switcher title-format option to show `App Name: Window Title` rows in Settings.
- Added shortcut syntax documentation and parser support for `tab`, `space`, `return`, `escape`, `delete`, arrow keys, letters, digits, and `backtick` / `` ` ``.

## phase-1 (unreleased)
- Added a macOS menu bar app scaffold (`StayHereApp`) with current-space title display.
- Added space naming persistence at `~/Library/Application Support/StayHere/spaces.json`.
- Added settings UI to rename spaces and reorder display order.
- Added HUD overlay shown on detected space changes.
- Added Debug menu actions for copying JSON state and opening log directory.
- Added core CGS bridge for active-space and managed-space discovery with polling fallback.
