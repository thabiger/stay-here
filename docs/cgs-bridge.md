# CGS Bridge — Private API Surface & Health Check

## Overview

StayHere depends on four private CoreGraphics (CGS) symbols resolved at runtime via `dlopen`/`dlsym`. These symbols are not part of the public macOS API and may change or be removed in future macOS releases. This document describes the symbol surface, failure semantics, health-check behavior, and a verification checklist for macOS updates.

## Symbol Table

| Symbol | Role | Fallback | Used By | Failure Behavior | Degraded Feature |
|---|---|---|---|---|---|
| `CoreGraphics.dlopen` | **critical** | — | all CGS methods | Every CGS method returns default | App core dead — no space data |
| `_CGSDefaultConnection` | **critical** | `CGSMainConnectionID` | all CGS methods | Every CGS method returns default | App core dead — no space data |
| `CGSGetActiveSpace` | **required** | — | `activeSpaceID()` | Returns `nil` | Status bar title, HUD, refresh trigger unknown |
| `CGSCopyManagedDisplaySpaces` | **required** | — | `managedSnapshot()` | Returns empty `ManagedSnapshot` | Space list/names/ordering empty (core feature) |
| `CGSCopySpacesForWindows` | **optional** | — | `spacesForWindow(windowID:)` | Returns `[]` | Window switcher space scoping broken |

### Role Semantics

- **critical**: Missing ⇒ every CGS-backed method returns its default; the app's core functionality is dead.
- **required**: Missing ⇒ a key feature degrades (active-space tracking or space list), but the app still launches and other features work.
- **optional**: Missing ⇒ a convenience feature degrades (window switcher scoping), but the app fully functions otherwise.

### Notes

- `switchByDesktopShortcut(index:)` uses **no** CGS symbols — only public `CGEvent` API — so it is unaffected by CGS symbol drift.
- The code already demonstrates forward-compatibility awareness: `_CGSDefaultConnection` needed a `CGSMainConnectionID` fallback in a prior macOS release.
- Symbols are resolved once per process (first access) and cached as lazy static function pointers; `dlsym` is never called on hot paths.
- `CGSCopySpacesForWindows` returns a flat space list (union of spaces containing any of the given windows) — it does **not** support per-window batched lookups. Consequently, `spacesForWindow(windowID:)` remains one IPC call per window ID by design.
- `spacesForWindow(windowID:)` is memoized with a 3 s TTL in `CGSSpacesCache` (thread-safe via `NSLock`, self-healing on expiry). This reduces redundant IPC when the same window is resolved multiple times within a brief window (e.g., filter + grouper, or rapid re-opens after settings-change invalidation).

## Health Check

### API

```swift
func bridgeHealth() -> CGSBridge.HealthReport
```

Defined on `CGSBridgeProtocol` with a default implementation returning `.notApplicable`. Only the concrete `CGSBridge` overrides it with real symbol resolution checks.

### Behavior

1. Returns `.notApplicable` immediately in test/CI environments (`RuntimeEnvironment.isAutomationSession`).
2. In production, resolves each symbol individually and reports per-symbol status.
3. Runs a functional smoke probe: calls `managedSnapshot()` to verify payload parsing still works (catches format drift that symbol resolution alone cannot detect).
4. `isHealthy` is `true` only when all critical+required symbols resolved AND the smoke probe returned data.

### Output Surface

- **Startup log**: On app launch, `AppRuntimeCoordinator.applicationDidFinishLaunching()` emits:
  - `logger.error("cgs-bridge DEGRADED: ...")` — always written to `~/Library/Logs/StayHere/stayhere.log`.
  - `logger.info("cgs-bridge healthy: ...")` — written only when Diagnostics is enabled (per `FileLogger.isInfoEnabled`).

## Injection-Point Contract

All consumers accept `any CGSBridgeProtocol`:

| Module | Consumer | Parameter Type |
|---|---|---|
| Core | `SpaceStateManager` | `cgsBridge: any CGSBridgeProtocol` |
| Core | `SwitchSpaceUseCase` | `cgsBridge: any CGSBridgeProtocol` |
| Core | `SpaceSwitcherService` | `cgsBridge: any CGSBridgeProtocol` |
| Core | `SpaceSwitchExecutor` | `cgsBridge: any CGSBridgeProtocol` |
| Core | `MissionControlShortcutCheck` | `check(cgsBridge: any CGSBridgeProtocol)` |
| Activation | `WindowIndex` | `cgsBridge: any CGSBridgeProtocol` |
| App | `AppCompositionRoot` | `cgsBridge: any CGSBridgeProtocol` |
| App | `CompositionServices` | `cgsBridge: any CGSBridgeProtocol` |
| App | `WindowListProvider` | `cgsBridge: any CGSBridgeProtocol` |

The only production reference to the concrete `CGSBridge.live` is the composition root (`AppDelegate.swift`). Six mock conformers exist in tests.

## macOS-Release Verification Checklist

After each macOS update, verify:

1. Run the app and enable **Diagnostics** in Settings.
2. Check `~/Library/Logs/StayHere/stayhere.log` for `cgs-bridge DEGRADED`.
3. Verify functional behavior:
   - [ ] Space list populates with names
   - [ ] Status bar shows the current space name
   - [ ] Ctrl+1..9 switching works
   - [ ] Window switcher scopes by space

If degraded, the log line lists exactly which symbols are missing and their roles.

## Future Work

- Extract symbol resolution into a dedicated module for cleaner isolation. The unsafe code is currently confined to `CGSBridge.swift` (205 lines), so this is deferred for marginal benefit.
- Keep the symbol table in sync via `CGSSymbol` constants in code — the single source of truth.
