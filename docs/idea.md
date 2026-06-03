# Named Spaces — product idea

**Named Spaces** is a macOS menu bar app that makes **Spaces** (virtual desktops) easier to recognize, reason about, and work with. It adds names you choose and smarter behavior when you click apps in the Dock.

This document describes *what we are building and why*. Technical phases, APIs, and delivery gates live in [`implementation-plan.md`](implementation-plan.md).

---

## The problem

macOS Spaces are powerful: separate desktops for work, personal tasks, meetings, or deep focus. In practice, many people hit the same friction:

1. **Spaces are anonymous.** Mission Control labels them “Desktop 1”, “Desktop 2”, and so on. You cannot give them meaningful names in the system UI, so it’s easy to forget which space is which—especially with more than two or three desktops.

2. **The Dock ignores your current space.** The Dock shows every running app, not just the ones with windows on *this* desktop. That noise makes it harder to see what actually belongs where.

3. **Clicking a Dock icon often yanks you to another space.** If an app is already open on a different desktop, macOS may switch spaces to show that window. The switch can be subtle; you end up on the wrong desktop without intending to. For single-window apps (Notes, many utilities), there is no “open another window here”—only “go where the window already lives.”

Named Spaces targets these three pain points directly.

---

## The vision

**Each Space should feel like a named room**, not an numbered slot.

When you change desktops, you should immediately know *where you are*. When you click an app, the Mac should respect *where you are*: show or create work on *this* desktop instead of teleporting you elsewhere.

Named Spaces sits alongside Mission Control—it does not replace Apple’s space switcher. It adds a persistent layer of **labels** and **intent-aware activation** for people who live in multiple desktops every day.

---

## What the app does

### 1. Visible space names

You assign a **name** (and optionally emoji or color) to each Space—e.g. “Work”, “Personal”, “Calls”.

Those names appear where you look all day:

- In the **menu bar** (current space + quick switcher).
- In a short **on-screen hint** when you change spaces, so you’re never guessing “was that Desktop 3 or 4?”

Names are **stored by Named Spaces** and stay tied to each desktop across restarts. They are meant for *your* workflow, not for renaming thumbnails inside Apple’s Mission Control screen (macOS does not offer a supported way to do that).

### 2. Space switcher

Named Spaces includes a configurable, AltTab-style picker for moving between Spaces.

- The picker opens when you press the configured shortcut.
- Releasing the shortcut commits the highlighted Space only if you actually changed selection.
- The default shortcut is `Option+Tab`, but you can change it in Settings.

Shortcut syntax is plain text:

- Modifiers: `option` (or `alt`), `shift`, `control` (or `ctrl`), `command` (or `cmd`)
- Keys: `tab`, `space`, `return` / `enter`, `escape` / `esc`, `delete` / `backspace`, `left`, `right`, `up`, `down`, letters `a`-`z`, digits `0`-`9`, and `` ` `` / `backtick` / `grave` / `tilde`
- Example: `command+backtick`, `control+space`, `option+shift+tab`

### 3. Space-aware Dock clicks

When you click an app in the Dock, Named Spaces applies rules based on **the Space you’re on now**:

| Situation | Intended behavior |
|-----------|-------------------|
| App not running | Launch it on the **current** Space. |
| App running, window already on **this** Space | Bring that window forward; **stay** on this Space. |
| App running, but only on **other** Spaces, and the app allows multiple windows | Open a **new window** on the current Space (e.g. browser, terminal). |
| App running, but only on other Spaces, and the app is effectively **single-window** (e.g. Notes) | **Move** the existing window to the current Space and focus it on a normal click—without silently switching them to another desktop. |

The Dock behavior is controlled by a single checkbox:

- **Disabled**: stock macOS behavior for Dock clicks.
- **Enabled**: Named Spaces intercepts Dock clicks for multi-window apps as above; single-window apps are handled on a normal click.

The goal is predictable, local behavior: *“I’m on Work; I clicked Chrome; I’m still on Work.”*

---

## Who it’s for

- People who keep **3+ Spaces** for different contexts (work, personal, admin, focus).
- Developers and creatives who **context-switch** often and dislike losing track of which desktop they’re on.
- Anyone frustrated by **unexpected space jumps** when clicking Dock icons.

It is **not** a full window manager replacement (unlike tiling tools or alternate “workspace” systems). It enhances **Apple’s built-in Spaces**, not replaces them.

---

## How it should feel in daily use

**Morning:** You land on “Work”. The menu bar says **Work**; the HUD confirms it when you swipe in from a personal desktop.

**Midday:** You’re on “Personal”. Chrome is open only on Work. You click Chrome in the Dock—a new window opens on Personal; you never leave Personal.

**Afternoon:** You need Notes on Work, but its window is on Personal. You click Notes on Work—the note window moves here; you never get whisked to Personal without meaning to.

**Optional:** Dock clicks stay local and predictable, so you can keep working on the desktop you chose.

---

## What we are not promising (honest limits)

Being clear early helps teammates and future users:

- **Mission Control thumbnails** will still show Apple’s default “Desktop N” labels unless macOS changes; our names live in Named Spaces UI.
- **Every app** may not support “new window on this Space” equally; some need special handling or may behave like stock macOS.
- **Fullscreen windows** and some system apps have restrictions on moving between Spaces.
- The app is planned as a **direct-download, notarized** utility—not a Mac App Store build with a reduced feature set.

Details and mitigations are in the implementation plan.

---

## Recommended macOS settings

For the best experience, users should:

- Turn off **“Automatically rearrange Spaces based on most recent use”** (keeps desktop order stable).
- Turn off **“When switching to an application, switch to a Space with open windows for the application”** (so Named Spaces can own that logic instead of fighting the system).

Onboarding will call these out; they are part of the product story, not hidden implementation detail.

---

## Product shape (at a glance)

| Aspect | Direction |
|--------|-----------|
| **Form factor** | Menu bar app (minimal presence, no Dock icon for Named Spaces itself) |
| **Platform** | macOS, recent versions (exact minimum TBD during development) |
| **Distribution** | Signed/notarized download; power-user features documented clearly |
| **Privacy** | Local-only configuration; no account or cloud required for core features |

---

## Name and positioning (working)

- **Working name:** Named Spaces (repository: `macos-named-spaces`)
- **One-line pitch:** *Name your Mac desktops, stay on the Space you chose, and keep app launches predictable.*
- **Longer pitch:** Named Spaces makes macOS Spaces work the way multi-desktop users expect: labeled rooms, predictable app launches, and better control over what happens when you click a Dock icon, without abandoning Mission Control.

Names and marketing copy can evolve; this doc captures intent, not final branding.

---

## Relationship to other docs

| Document | Audience | Purpose |
|----------|----------|---------|
| **`idea.md` (this file)** | Team, contributors, future site visitors | *Why* and *what*—product vision and behavior |
| [`implementation-plan.md`](implementation-plan.md) | Implementers | *How*—phases, APIs, gates, tests |
| `docs/gates/` (future) | You + reviewers | Per-phase approval checklists |

---

## Seeds for public site / README (later)

When you write the public site or App Store–style page, these sections map cleanly from this doc:

1. **Hero** — one-line pitch + screenshot (menu bar + HUD).
2. **The problem** — anonymous desktops, Dock noise, surprise space switches.
3. **Features** — names, smart clicks, and space-aware activation.
4. **How it works** — short scenarios (work/personal/Notes).
5. **Requirements** — macOS version and permissions.
6. **FAQ** — Mission Control names, vs tiling window managers, privacy.
7. **Download** — link to release + setup guide.

You can lift paragraphs from this file with light editing for tone (marketing vs. internal).

---

## Status

**Early development.** The product idea is defined; implementation follows the phased plan with explicit review after each phase. Feedback on this document is welcome before public messaging is finalized.
