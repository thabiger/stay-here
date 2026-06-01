# PHASE-1 Gate — Foundation App (MVP)

## Goal
Deliver a debug-build menu bar app that shows and persists custom space names with a space-switch HUD and debug diagnostics.

## In scope
- Menu bar label for current space name
- Settings UI to rename spaces
- Display-only list reorder in settings
- Space change observer with polling fallback
- Persistence and unknown-space reconciliation
- HUD on space change
- Debug menu with JSON state copy and log access

## Out of scope
- Dock click interception and activation policy
- Event taps and Dock AX hit-testing
- Dock filtering or scripting additions

## How to build & run
```bash
swift build
swift run NamedSpacesApp
```

## What you should see
- A menu bar item labeled with the active space name
- `Settings…` showing editable names for discovered spaces
- HUD text near top-center after space change events

## Manual test checklist
1. ☐ Launch app and confirm menu bar shows a custom name (or "Unnamed space").
2. ☐ Rename a space in Settings, switch spaces, and verify HUD + menu bar update.
3. ☐ Quit and relaunch; verify names persisted.
4. ☐ Create a new Mission Control space; verify it appears as "Unnamed space".
5. ☐ Use Debug > Copy space state and verify JSON contains active space and labels.
6. ☐ Use Debug > Open logs and confirm logs exist in `~/Library/Logs/NamedSpaces`.
7. ☐ Confirm Dock icon behavior remains stock macOS.

## Automated checks
- `swift build`

## Known limitations
- `CGSBridge` relies on private symbols that may vary by macOS build.
- Poll fallback refreshes every 1 second and may show brief lag.
- Reorder is app display-order only; Mission Control ordering is unchanged.

## Rollback
- Quit the app from menu bar.
- Delete `~/Library/Application Support/NamedSpaces/spaces.json`.
- Delete `~/Library/Logs/NamedSpaces/` if desired.

## Verification
- Date:
- macOS build:
- Notes:

## Decision
- **Status:** Pending
- **Date:**
- **Tester:** thabiger
- **Notes:**
