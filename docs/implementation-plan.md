---
title: macOS Named Spaces — Implementation Plan
overview: A notarized macOS menu-bar utility that adds persistent space names and space-aware app activation (without unwanted space jumps). Greenfield; Swift + private CGS APIs modeled on AltTab/yabai prior art.
updated: 2026-06-05
canonical: true
---

# macOS Named Spaces — Feasibility and Development Plan

> **Canonical plan** for this repository. Phase sign-off lives in [`docs/gates/`](gates/). Do not start phase *N+1* until [`docs/gates/PHASE-N.md`](gates/PHASE-0.md) is **Approved** or **Approved with caveats**.

## Plan At A Glance

| Phase | What we are shipping | Exit criteria |
|-------|----------------------|---------------|
| **0 - Spike** | Validate CGS APIs, space IDs, and move/focus behavior on your Mac | `docs/SPIKE_REPORT.md` complete; `phase-0` tag; gate approved |
| **1 - Foundation** | Menu bar app with persistent space names, HUD, and debug tooling | Current space name visible; names persist; `phase-1` tag; gate approved |
| **2 - Activation** | Dock click interception, activation policy, new-window heuristics, and safe single-window moves | Dock clicks behave as intended with no unwanted space jumps; `phase-2` tag; gate approved |
| **3 - Polish + Release** | Onboarding, logging, compatibility docs, release hardening, update notifications, and signed DMG packaging | Release build works on a fresh setup; manual update notice works; `v1.0.0` or release tag; gate approved |

Update note: the first update experience is a GitHub Releases check that informs the user and opens the release page. Sparkle is deferred until you have the Apple Developer Program account and Developer ID signing in place.

## Implementation checklist

| ID | Task | Status |
|----|------|--------|
| spike-cgs | Phase 0 spike: CGS + window move/focus validation; deliver SPIKE_REPORT.md + gate-0 approval | pending |
| gate-0-approve | You: run Phase 0 checklist, sign off in docs/gates/PHASE-0.md before Phase 1 starts | pending |
| core-app-mvp | Phase 1: menu-bar app (names/HUD only); deliver PHASE-1 demo + gate-1 approval | pending |
| gate-1-approve | You: run Phase 1 checklist, sign off in docs/gates/PHASE-1.md before Phase 2 starts | pending |
| activation-engine | Phase 2: ActivationPolicy + Dock intercept; deliver PHASE-2 demo + gate-2 approval | pending |
| gate-2-approve | You: run Phase 2 checklist, sign off in docs/gates/PHASE-2.md before Phase 3 starts | pending |
| update-notifications | Phase 3: GitHub Releases version check, update available UI, and manual install link now; Sparkle later | pending |
| release-prep | Phase 3: onboarding, logging, compatibility docs, update hardening, and release packaging; deliver RELEASE gate + final sign-off | pending |
| gate-3-approve | You: run Phase 3 checklist, sign off in docs/gates/PHASE-3.md before release | pending |

---

## Feasibility summary

| Goal | Feasible? | How |
|------|-----------|-----|
| **(a) Visible space names** | **Yes, with limits** | Persistent names in *your* UI (menu bar, HUD on switch, optional floating labels). **Not** inside Apple’s Mission Control thumbnails via supported APIs. `CGSSpaceSetName` exists privately but does not reliably change Mission Control labels. |
| **(b) Smart app activation** | **Yes, hard** | Combine space/window queries (private CGS + `CGWindowListCopyWindowInfo`) with Accessibility to focus/move windows. Intercepting Dock clicks is doable (event tap + AX on Dock), with a checkbox to enable/disable interception: when enabled, multi-window clicks are intercepted and single-window Dock clicks are handled on a normal click. Moving windows without switching spaces works on many macOS versions via `CGSMoveWindowsToManagedSpace`; breaks or tightens on newer releases—needs per-OS testing (you’re on **darwin 25.x**, so treat APIs as unstable). |

**User settings that must be documented (not optional for good UX):**

- Turn off **“Automatically rearrange Spaces based on most recent use”** (stable space index ↔ shortcuts).
- Turn off **“When switching to an application, switch to a Space with open windows for the application”** (this is exactly the behavior you want to replace in (b)).

---

## Target behavior (your spec → implementation)

```mermaid
flowchart TD
  dockClick[DockIconClick] --> intercept[InterceptViaEventTap]
  intercept --> classify[ClassifyAppState]
  classify --> notRunning[NotRunning]
  classify --> hasWinHere[WindowOnCurrentSpace]
  classify --> runningElsewhere[RunningNoWindowHere]
  classify --> singleWindow[SingleWindowApp]
  notRunning --> launch[NSWorkspaceLaunch]
  hasWinHere --> focus[AXFocusWindowOnSpace]
  runningElsewhere --> newWin[OpenNewWindowHeuristic]
  singleWindow --> moveWin[CGSMoveWindowsToManagedSpace]
  moveWin --> focus
  newWin --> focus
```

**Activation decision table (core of feature b):**

1. Resolve **current space ID** per display (`CGSGetActiveSpace` / `CGSCopyManagedDisplaySpaces` — same pattern as [alt-tab-macos PrivateApis.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/PrivateApis.swift) and [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)).
2. For clicked app (bundle ID / PID):
   - **Not running** → `NSWorkspace.shared.openApplication(...)` (or `launchApplication`).
   - **Running** → enumerate windows (`CGWindowListCopyWindowInfo` + `CGSCopySpacesForWindows` for space membership).
   - **≥1 window on current space** → raise best candidate (main/focused, else MRU) via AX (`kAXRaiseAction`, unminimize if needed) **without** changing active space.
   - **No window on current space, multi-window app** → trigger “new window” (tiered: AppleScript menu item → `⌘N` via AX → app-specific handlers for Chrome/Terminal/etc.).
   - **Single-window app** (heuristic: one non-minimized window in `CGWindowList`, or known bundle allowlist like Notes) → `CGSMoveWindowsToManagedSpace` then focus; if CGS fails on your OS build, fallback to [Orbit-style simulated drag](https://github.com/thirteen37/Orbit) (Accessibility + space-switch shortcut).

**Space names (feature a):**

- Persist `spaceID → { name, emoji?, color? }` in `~/Library/Application Support/NamedSpaces/spaces.json`.
- On space create/destroy/reorder, reconcile mapping (detect new IDs, prune stale).
- **Visible names** (pick 2–3 surfaces in v1):
  - Menu bar: current space name + switcher list (proven pattern: Spaceman, Desktop Space Renamer).
  - Brief **HUD overlay** (1–2s) on space change showing name (high signal, low Mission Control dependency).
  - Optional: small **on-screen edge labels** when Mission Control is open (AX read of MC UI is fragile; defer to v2).

---

## Architecture

One deliverable (single app, shared modules):

| Component | Role | Runs as |
|-----------|------|---------|
| **NamedSpaces.app** | UI, settings, space registry, activation engine, Dock click interception | Menu bar agent (`LSUIElement`) |

Shared Swift package / static lib:

- `CGSBridge` - typed bindings for `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`, `CGSCopySpacesForWindows`, `CGSMoveWindowsToManagedSpace`, and space-change notifications.
- `SpaceModel` - space ID, display UUID, index, user label.
- `WindowIndex` - window ID ↔ spaces ↔ PID ↔ AX element (lazy AX for off-space windows).
- `ActivationPolicy` - state machine for dock-click and hotkey paths.

**Permissions (all required for full feature set):**

- Accessibility (AX for focus + Dock element hit-testing).
- Input Monitoring (global mouse event tap for Dock clicks).
- Automation (optional AppleScript for "New Window").

**Distribution:** Developer ID signed + notarized `.dmg`; **not** App Store. Private CGS from your process is enough for move/focus on many systems.

---

## Implementation rules (phase gates and your approval)

Development is **strictly sequential**. No work on phase *N+1* begins until phase *N* is **signed off by you** in the repo.

### Core rules

1. **One phase = one mergeable unit.** Each phase ends on a git tag `phase-N` (e.g. `phase-0`, `phase-1`) and a filled gate document (below).
2. **No scope creep inside a phase.** If a task belongs to a later phase, it is deferred and logged in `docs/BACKLOG.md`, not implemented early.
3. **Every phase ships observable behavior** you can try without reading code: a CLI, menu item, HUD, log file, or installer step.
4. **Diagnostics are always on** during development: verbose logging to `~/Library/Logs/NamedSpaces/` and a **Debug** submenu (copy state, open logs, dump space/window JSON).
5. **Rollback:** each phase documents how to disable it in the gate file.
6. **Agent stops at the gate.** After delivering phase artifacts, implementation pauses until you mark the gate **Approved** (see below).

### Gate workflow (repeat every phase)

```mermaid
stateDiagram-v2
  direction LR
  implement[ImplementPhaseN] --> deliver[DeliverArtifacts]
  deliver --> demo[YouRunChecklist]
  demo --> decision{Approved?}
  decision --> yes: PhaseNplus1
  decision --> no: fix[FixOrDescope]
  fix --> deliver
```

| Step | Owner | Action |
|------|--------|--------|
| 1. Implement | Agent | Only scope listed under "Phase N - In scope"; update `CHANGELOG.md` |
| 2. Deliver | Agent | Binaries/scripts + gate doc + test steps (see per-phase tables) |
| 3. Demo | **You** | Run manual checklist; note pass/fail in gate doc |
| 4. Decide | **You** | Set gate status to `Approved`, `Approved with caveats`, or `Rejected` |
| 5. Proceed | Agent | **Only if `Approved` or `Approved with caveats`** - then start next phase |

### Gate document (repo contract)

For each phase, maintain:

- [`docs/gates/PHASE-0.md`](gates/PHASE-0.md) ... `PHASE-3.md` - from template [`docs/gates/TEMPLATE.md`](gates/TEMPLATE.md)

Template sections (you fill **Verification** and **Decision**):

- **Goal** - one sentence
- **In scope / Out of scope** - copied from plan
- **How to build & run** - exact commands (Debug build path)
- **What you should see** - expected UI/log output (screenshots optional)
- **Manual test checklist** - numbered steps with ☐ boxes
- **Automated checks** (if any) - `swift test`, script exit codes
- **Known limitations** - honest list for this phase only
- **Rollback** - how to undo
- **Verification** (your notes: date, macOS build, pass/fail per item)
- **Decision** - `Approved` | `Approved with caveats` | `Rejected` + free text

**Approval syntax** (you edit the gate file):

```markdown
## Decision
- **Status:** Approved
- **Date:** 2026-06-01
- **Tester:** thabiger
- **Notes:** CGS move works; caveats documented.
```

Rejected gates block the next phase; agent addresses only items under **Required fixes** you list in the same file.

### Repo artifacts (created in Phase 0 setup)

| Path | Purpose |
|------|---------|
| `docs/gates/TEMPLATE.md` | Gate template |
| `docs/gates/PHASE-*.md` | Per-phase sign-off |
| `docs/SPIKE_REPORT.md` | Phase 0 API matrix (pass/fail per API on your OS) |
| `docs/BACKLOG.md` | Deferred ideas |
| `CHANGELOG.md` | User-visible changes per phase |
| `Scripts/phase-demo.sh` | Prints current space IDs, window→space map (for your verification) |

### Build flavors

| Flavor | When | What it includes |
|--------|------|------------------|
| **Debug** | Every gate | Verbose logs, "Debug" menu, optional CGS trace |
| **Phase-N** tag | After your approval | Same as Debug unless noted |
| **Release** | Phase 3 only | Notarized, logs default off |

You test **Debug** builds at every gate unless the phase explicitly requires the installer.

### What you approve (by phase)

| Phase | You are approving that... | You are **not** approving yet |
|-------|---------------------------|------------------------------|
| **0** | APIs and window move/focus behavior are viable on your Mac; risks are documented | Any UI product |
| **1** | Space names persist; HUD/menu reflect **current** space correctly | Dock click behavior |
| **2** | Dock-click rules (b) work for agreed test apps; no unwanted space jumps in tests | Onboarding and release polish |
| **3** | Installer, onboarding, release build; safe rollback documented | New features |

### Escalation

- **Approved with caveats:** next phase starts; caveats copied into `docs/BACKLOG.md` with target phase.
- **Rejected:** agent posts **Required fixes** in gate file; no new phase work until re-test and approval.

---

## Phase 0 - Spike (1-2 weeks, de-risk before UI)

Validate on **your machine (darwin 25.x)**:

1. List spaces and read active space ID after switching.
2. For a test app (TextEdit): detect windows per space; move one window with `CGSMoveWindowsToManagedSpace` **without** user-visible space switch.
3. Focus window on another space from current space (measure: does macOS animate space change?).
4. Confirm the app can move or focus a test window without a visible space jump on your OS.

**In scope:** `CGSBridge` prototype, `Scripts/phase-demo.sh`, `docs/SPIKE_REPORT.md`, gate template + `PHASE-0.md`.

**Out of scope:** Menu bar app, event taps, installer polish.

**Exit criteria (agent):** `docs/SPIKE_REPORT.md` complete; `Scripts/phase-demo.sh` runs without crash; gate doc delivered.

**Your approval checklist (Phase 0):**

1. Run `Scripts/phase-demo.sh` - prints >=1 space ID; ID changes when you switch spaces (Ctrl+←/→).
2. Open TextEdit on Space A; switch to Space B; script shows window on Space A only.
3. Run spike "move window" command - window appears on current space **without** you seeing Mission Control switch (or report failure in gate).
4. Read `docs/SPIKE_REPORT.md` - understand which APIs are **go / no-go** on your OS.
5. Fill **Decision** in `docs/gates/PHASE-0.md`.

**Deliverables:** tag `phase-0`; no `NamedSpaces.app` required yet.

---

## Phase 1 - Foundation app (MVP)

**Repo layout** (greenfield at repository root):

```
NamedSpaces/
  App/                 # Menu bar app
  Core/                # SpaceModel, WindowIndex, CGSBridge
  Activation/          # ActivationPolicy
  Resources/
  Shared/              # IPC messages
```

**Implement:**

- Menu bar app with Settings: name each space, reorder list (display-only; actual reorder still via Mission Control).
- Space change observer (NSWorkspace active space notifications + CGS poll fallback).
- Persistence + "unknown space" handling when IDs churn.
- HUD: show name on space switch.

**In scope:** Menu bar label, Settings to rename spaces, HUD on space change, persistence, space ID reconciliation, Debug menu (dump JSON, open logs).

**Out of scope:** Dock click override, `ActivationPolicy`, event tap.

**Your approval checklist (Phase 1):**

1. Launch `NamedSpaces.app` (Debug) - menu bar shows **custom name** for current space (not only "Desktop 1").
2. Rename Space 2 in Settings -> switch to Space 2 -> HUD shows new name within ~1s.
3. Quit app, relaunch - names still correct (persistence).
4. Create a new Space in Mission Control - app shows "Unnamed space" or prompts to name (document actual behavior).
5. Toggle **Reduce motion** off/on - HUD still acceptable (no crash).
6. Debug -> **Copy space state** - paste JSON; space IDs match `phase-demo.sh`.
7. Confirm Dock clicks still behave **stock macOS** (no interception yet).
8. Fill **Decision** in `docs/gates/PHASE-1.md`.

**Deliverables:** tag `phase-1`; demo video or screenshot optional in gate doc.

---

## Phase 2 - Space-aware activation (feature b)

1. **Dock click interception**: `CGEvent.tapCreate` on mouse down/up; hit-test Dock via AX (`AXUIElementCreateApplication(dockPID)`); map to bundle ID; **consume** event and run `ActivationPolicy` (Stack Overflow pattern: activation from tap may require brief `NSApp.activate` - minimize menubar flicker).
2. **Window index** refresh on space change, app launch/terminate, window create/destroy (NSWorkspace + optional `NSApplication` notifications where available).
3. **Single-window detection** heuristic + per-bundle overrides plist in app bundle.
4. **New-window strategies** pluggable per `bundleID`.
5. Settings checkbox: "Enable Dock click interception" (`Enabled` / `Disabled`). When enabled, multi-window app clicks are intercepted as today; single-window app clicks are ignored by default and only use Named Spaces behavior when **Option** is held. When disabled, Dock clicks follow stock macOS behavior.

**In scope:** `WindowIndex`, `ActivationPolicy`, Dock event tap, Settings for intercept mode, structured activation log lines.

**Out of scope:** Extra Dock UI changes beyond click interception.

**Prerequisite:** Mission Control settings from plan (auto-rearrange off; "switch to space with open windows" **off**).

**Your approval checklist (Phase 2):**

Use **3 spaces** (Work / Personal / Scratch) with distinct names. Record macOS version in gate.

| # | Setup | Action | Expected (pass) |
|---|--------|--------|------------------|
| 2.1 | Chrome window only on **Work** | On **Work**, click Chrome in Dock | Focuses Chrome; **stay on Work** |
| 2.2 | Chrome only on **Work** | On **Personal**, click Chrome | New Chrome window (or documented handler) on **Personal**; **stay on Personal** |
| 2.3 | Notes window only on **Work** | On **Personal**, click Notes | Window moves to **Personal** OR focuses without visible space switch; **stay on Personal** |
| 2.4 | Safari not running | Click Safari | Safari opens on **current** space |
| 2.5 | TextEdit minimized on **current** space | Click TextEdit | Unminimizes on **current** space |
| 2.6 | Intercept mode: **Enabled** | Click without Option on a multi-window app | NamedSpaces behavior; stay on current Space |
| 2.7 | Intercept mode: **Enabled** | Click without Option on a single-window app | NamedSpaces behavior; move/focus window as needed |
| 2.8 | Intercept mode: **Enabled** | Option+click on a single-window app | NamedSpaces behavior; move/focus window as needed |
| 2.9 | Intercept mode: **Disabled** | Any Dock click | Stock macOS behavior |
| 2.10 | After each test | Check Debug log | One `activation` record with decision reason when interception is enabled |

**Optional / document fail:** fullscreen app (2.11), Electron app (2.12).

**Rollback test:** disable "Enable Dock click interception" in Settings - stock behavior restored without reinstall.

Fill **Decision** in `docs/gates/PHASE-2.md`. Any failed row -> `Rejected` or `Approved with caveats` with row numbers listed.

**Deliverables:** tag `phase-2`.

---

## Phase 3 - Polish and release

- Onboarding wizard (permissions + Mission Control settings).
- Logging pane for support (CGS errors and activation decisions).
- Per-macOS version compatibility table in README.
- Crash isolation: if Dock click interception misbehaves, auto-disable interception and show alert.
- Update notifications: check GitHub Releases, show a non-blocking "new version available" notice, and open the release page or direct download link from the app.

**In scope:** Onboarding wizard, notarized DMG, README compatibility table, Launch at Login, default log level off in Release, GitHub-based update notifications with manual install path.

**Your approval checklist (Phase 3):**

1. Fresh VM or second user account: run installer from DMG - permissions + Mission Control checklist shown.
2. Release build: no Debug menu unless "Enable debug" in Settings.
3. Trigger an update check against a newer GitHub Release - app shows the update notice and opens the correct release/download page.
4. Reboot - app still works and settings persist.
5. `docs/gates/PHASE-3.md` - final **Release Approved** sign-off.

**Deliverables:** tag `v1.0.0` (or `phase-3` + release tag).

---

## Prior art to study (not necessarily fork)

| Project | Use for |
|---------|---------|
| [alt-tab-macos](https://github.com/lwouis/alt-tab-macos) | CGS bindings, `CGSCopySpacesForWindows`, cross-space focus, animation tricks |
| [Orbit](https://github.com/thirteen37/Orbit) | AX fallback to move windows between spaces |
| [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) | Fast space switch / animation suppression |
| [Spaceman](https://github.com/Jaysce/Spaceman) | Menu bar space names (public-API-friendly subset) |

---

## Risks (be explicit with users)

| Risk | Impact |
|------|--------|
| macOS updates break CGS symbols | Frequent maintenance; version pin in README |
| Sonoma+ window “ownership” model | Move/focus may fail for some windows -> AX fallback only |
| App Store | Out of scope for full vision |
| “New window” not universal | Some apps need custom handlers |

---

## Suggested v1 scope (shippable)

**Ship first:** names + HUD + menu bar, activation with Dock intercept, CGS move for single-window apps, documented Mission Control settings, and basic update notifications that point users to the latest release.

Defer: Mission Control thumbnail labels, fullscreen space moves, App Store build.

---

## Success criteria

- User can see **current space name** without opening Mission Control.
- Clicking Dock icon for Chrome with a window on **this** space focuses it and **does not** change spaces.
- Clicking Notes when its window is on another space **moves** it here (or opens if quit) without user noticing a space switch.
- Survives reboot with Launch at Login and documented settings restore.
