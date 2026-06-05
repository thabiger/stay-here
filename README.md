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

## Permissions

StayHere needs these permissions in System Settings:

- **Accessibility** - used to focus apps, react to Dock interactions, and control space-related behavior.
- **Input Monitoring** - used for global input handling, including the switcher and Dock click interception.

If you change the app bundle identifier, signing identity, or reinstall the app under a different name, macOS may treat it as a different app and ask for permissions again.

## Mission Control shortcuts

The app checks that these macOS shortcuts are enabled:

- `Control+1` for Desktop 1
- `Control+2` for Desktop 2
- `Control+3` for Desktop 3
- `Control+4` for Desktop 4
- `Control+5` for Desktop 5
- `Control+6` for Desktop 6

You can enable them in:

`System Settings > Keyboard > Keyboard Shortcuts > Mission Control`

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
