# PHASE-2 Gate - Space-aware Activation

## Goal
Deliver Dock click interception plus activation policy decisions that keep users on the current space whenever possible.

## In scope
- `WindowIndex` for per-app window summaries
- `ActivationPolicy` decision engine
- Dock left-click event tap interception with AX hit-testing
- Settings toggle for interception mode (`Replace`, `Option-only`, `Disabled`)
- Structured `activation` log records in `~/Library/Logs/NamedSpaces/namedspaces.log`

## Out of scope
- Dock scripting addition injection
- Real Dock tile visibility filtering

## How to build & run
```bash
swift build
swift run NamedSpacesApp
```

## What you should see
- New Settings section: `Dock Click Interception`
- Dock icon clicks trigger `activation ... decision=...` log lines
- Option-only mode leaves normal clicks untouched and intercepts Option+click

## Manual test checklist
1. ☐ Confirm Mission Control settings prerequisites are set (auto-rearrange OFF, switch-to-app-space OFF).
2. ☐ 2.1: On Work, click Chrome when Chrome has a Work window only; verify focus on Work and no space jump.
3. ☐ 2.2: On Personal, click Chrome when Chrome only has Work windows; verify new window behavior on Personal.
4. ☐ 2.3: On Personal, click Notes when Notes has a single Work window; verify move/focus behavior without visible space switch.
5. ☐ 2.4: Click Safari when not running; verify launch on current space.
6. ☐ 2.5: Click minimized TextEdit on current space; verify unminimize/focus behavior.
7. ☐ 2.6/2.7: Switch to `Only when Option is held`; verify normal click is stock and Option+click uses NamedSpaces behavior.
8. ☐ 2.8: Confirm each click creates an `activation` log line with bundle, mode, current space, and decision.
9. ☐ Rollback: set mode `Disabled`; verify stock Dock behavior resumes.

## Automated checks
- `swift build`

## Known limitations
- Dock AX hit-testing depends on Accessibility/Input Monitoring permissions.
- New-window behavior currently uses a generic `Cmd+N` shortcut after activation; apps with custom flows may need bundle-specific handlers in later iterations.
- Single-window detection is heuristic (`<=1` standard window) and may need per-bundle overrides.

## Rollback
- In Settings, set Dock Click Interception to `Disabled`.
- Quit the app from menu bar to fully stop interception.

## Verification
- Date:
- macOS build:
- Notes:

## Decision
- **Status:** Pending
- **Date:**
- **Tester:** thabiger
- **Notes:**
