# StayHere

StayHere is a macOS menu bar app that helps you name your Spaces, switch between them more easily, and keep Dock clicks from sending you to the wrong desktop.

## What it does

- Lets you give each Space a custom name.
- Shows the current Space name in the menu bar.
- Shows a small HUD when you switch Spaces.
- Provides a configurable Space switcher picker.
- Provides a configurable Window switcher picker for windows on the current Space.
- Can intercept Dock clicks so app launches and window activation stay on the Space you are using.

## Setup checklist

For the best experience, set up StayHere in this order:

1. Grant the required macOS permissions.
2. Enable the Mission Control keyboard shortcuts.
3. Set your preferred Space and Window switcher shortcuts.
4. Optionally add single-window apps.
5. Turn off a couple of macOS Space behaviors that fight with the app.

## Permissions And Security

StayHere needs these permissions in System Settings:

- **Accessibility** - used to focus apps, react to Dock interactions, and control space-related behavior.

StayHere also uses a global mouse event tap when Dock click interception is enabled. That is what lets it notice Dock clicks and decide whether to handle them itself or let macOS proceed normally.

Some future app-specific actions may request **Automation** permission if StayHere needs to send Apple Events to another app, for example to trigger a target app's built-in `New Window` command. The current release does not rely on Automation for the core menu bar, Space, or window switching features.

If you change the app bundle identifier, signing identity, or reinstall the app under a different name, macOS may treat it as a different app and ask for permissions again.

## Distribution Model

StayHere is distributed outside the Mac App Store on purpose.

- The app depends on Accessibility for its core behavior.
- Dock click interception uses a global input event tap.
- StayHere reads and moves window/space state through private CGS APIs.

Those APIs are useful for this workflow, but they are private and can change across macOS releases. That means the app can need maintenance after system updates, and the exact behavior may vary between macOS versions.

The release model is direct download from GitHub Releases, with signed and notarized builds planned for public distribution.
Pull requests should also pass CI, dependency review, and CodeQL before changes are merged.

## Install From GitHub Releases

When you want to try a published build:

1. Open the latest release on GitHub.
2. Download the `StayHere.dmg` file if you want the usual drag-and-drop install, or `StayHere.zip` if you prefer a plain archive.
3. Open the downloaded file and copy `StayHere.app` into your `Applications` folder.
4. Launch the app from `Applications`.

Because test builds may be ad hoc signed or unsigned, macOS can show a warning the first time you open the app. If that happens, do one of these:

- Control-click the app and choose **Open**.
- Or open `System Settings > Privacy & Security` and allow the blocked app there.

If macOS asks for Accessibility permission, grant it so the app can manage Spaces and Dock interactions.

## Mission Control shortcuts

The app checks that Mission Control desktop shortcuts `Control+1` through `Control+9` are enabled.

You can enable them in:

`System Settings > Keyboard > Keyboard Shortcuts > Mission Control`

StayHere tries to pre-enable these shortcuts for Desktop 1 through Desktop 9 on first launch so future desktops keep working. If macOS does not pick up the change immediately, reopen StayHere and recheck the checklist.

StayHere uses these shortcuts internally for space switching, so they need to stay enabled.

## Space switcher shortcut

The space picker opens when you press the configured shortcut.

- Default: `option+tab`
- You can change it in the app Settings

Shortcut syntax is plain text:

- Modifiers: `option` or `alt`, `shift`, `control` or `ctrl`, `command` or `cmd`
- Keys:
  - `tab`
  - `space`
  - `return` or `enter`
  - `escape` or `esc`
  - `delete` or `backspace`
  - arrow keys: `left`, `right`, `up`, `down`
  - letters: `a` through `z`
  - digits: `0` through `9`
  - `` ` `` or `backtick` or `grave` or `tilde`

Examples:

- `control+space`
- `command+backtick`
- `option+shift+tab`

At least one modifier is required.

## Window switcher shortcut

The window picker opens when you press the configured shortcut.

- Default: `command+tab`
- It only shows windows on the current Space
- Each row includes the app icon to make the list easier to scan

Shortcut syntax is the same as the Space switcher.

In Settings, the Window Switcher section also lets you show minimized windows and hidden windows if you want a broader list.

## Single-window apps

In Settings, you can add bundle identifiers for apps that should behave like single-window apps.

Format:

- One bundle identifier per line
- Example: `com.apple.Notes`

These apps get special handling so a normal Dock click can move the existing window to the current Space instead of sending you to another desktop.

## Dock click interception

The Dock click interception toggle controls whether StayHere handles Dock clicks.

- **Enabled**: StayHere intercepts Dock clicks for multi-window apps and applies its Space-aware rules.
- **Disabled**: macOS handles Dock clicks normally.

## Recommended macOS settings

These settings are not strictly required, but they make StayHere behave more predictably:

- Turn off **Automatically rearrange Spaces based on most recent use**.
- Turn off **When switching to an application, switch to a Space with open windows for the application**.

## How it feels to use

- Rename your Spaces to things like `Work`, `Personal`, or `Calls`.
- Use the switcher shortcut to move between Spaces quickly.
- Click apps in the Dock without being surprised by a jump to another desktop.
- Keep Mission Control as the system Space manager while StayHere adds names and smarter behavior on top.

## Notes

- Mission Control itself still shows Apple’s default `Desktop N` labels. StayHere keeps your names inside the app UI.
- The app is designed as a menu bar utility, not a Dock app.
- Some fullscreen windows and system apps have macOS restrictions that limit space-moving behavior.
