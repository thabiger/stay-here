# StayHere

**StayHere protects your focus by keeping different contexts in separate Spaces.**

StayHere is a menu bar app for people who want to treat macOS Spaces as real workspaces, mental rooms for cognitive isolation of the different kinds of work we deal with every day in increasingly context-switching-heavy environments.

Being able to separate programming, reporting, communication, research, and all the other things we do into different Spaces is crucial if you want to stay focused and sane. Unfortunately, macOS does a lot to undermine that: unnamed desktops, a Dock that mixes apps from every Space, window switchers that ignore context, and magical teleportation abilities that move you to a different desktop without warning.

StayHere adds the layer Apple skipped: visible Space names, predictable Dock behavior that keeps work in the current Space, and switchers scoped to the desktop you are already in.

But don't get me wrong. I'm not here to compete with the many window switchers already available. There are plenty of apps doing a magnificent job when it comes to fancy switching, window previews, and visual navigation.

**My goal is different: I want to reduce chaos.**

I want to get rid of the chaos that makes us think navigating through a flood of window thumbnails is a productive way to work. I want each Space to contain only the tools relevant to the task at hand, so I don't even have to look for them among dozens of unrelated windows.

Click [here](https://www.youtube.com/watch?v=4eVp7_AZi8k) to watch the full presentation:

<p align="center">
  <a href="https://www.youtube.com/watch?v=4eVp7_AZi8k">
    <img
      src="https://img.youtube.com/vi/4eVp7_AZi8k/maxresdefault.jpg"
      alt="StayHere Demo"
      width="800"
    />
  </a>
</p>

For the full story behind the app, see [Your macOS Spaces Don't Respect Your Focus](https://medium.tnkrd.com/your-mac-keeps-moving-you-to-the-wrong-room-11e36483191a).

## With StayHere, you can:

- give your Spaces meaningful names such as Work, Writing, Calls, or Programming,
- see the current Space name in the menu bar,
- get a small popup whenever the active Space changes, so you always know where you are,
- make Dock clicks more predictable by preventing them from teleporting you to another Space where the selected app is already running,
- open a new application window in the current Space whenever possible,
- use window switchers scoped to the current Space, making navigation simpler and less distracting,
- control switching apps and spaces using built-in macOS Voice Control feature: [read more](docs/voice-control.md),
- use call and app switchers in multiple ways: with the classic keyboard shortcut hold-and-release method, hot corners, arrow keys, and more.

## Automation URLs

StayHere can now control its switchers through a custom `stayhere://` URL scheme, which makes it easier to attach them to voice tools or external launchers.

- `stayhere://window-switcher/open`
- `stayhere://space-switcher/open`
- `stayhere://switcher/next`
- `stayhere://switcher/previous`
- `stayhere://switcher/commit`
- `stayhere://switcher/select/N`
- `stayhere://switcher/close`

## Permissions and Security

StayHere needs these permissions and settings:

- **Accessibility** — required to focus apps, react to Dock interactions, and control space-related behavior.
- **Mission Control desktop shortcuts** — enable **Switch to Desktop 1** through **Switch to Desktop 9** in `System Settings > Keyboard > Keyboard Shortcuts > Mission Control`. StayHere uses these shortcuts internally for space switching, so they need to stay enabled.
- **Screen Recording** — (optional) for the richer window switcher experience. If you want window titles beside app names (`App Name: Window Title`), grant **Screen Recording** in `System Settings > Privacy & Security > Screen & System Audio Recording`. macOS hides other apps' window names until that permission is granted.

## Other Recommended macOS settings

The goal here is to deliver a focus-first experience to your workflow. Therefore I encourage you to run it with additional settings:

- Settings -> Desktop & Dock -> Automatically rearrange Spaces based on most recent use -> Off
- Settings -> Desktop & Dock -> When switching to an application, switch to a Space with open windows for the application -> Off (prevents teleporting to other spaces through Spotlight)
- Settings -> Desktop & Dock -> Group windows by application -> On
- Settings -> Desktop & Dock -> Displays have separate Spaces -> Off (it messes with Space locations across displays when a display disconnects)
- Settings -> Desktop & Dock -> Show suggested and recent apps in Dock -> Off (you should only see what you need to get work done in your Space)

## Distribution Model

The release model is direct download from GitHub Releases.

> [!WARNING]
> Current releases are <strong>not notarized</strong>, so macOS may warn that StayHere is from an unidentified developer or could be dangerous when you first open it. The app is released for free, which means it does not bring in any funds to cover Apple Developer Program costs for signing and notarization. If the app helps you, I would appreciate any <a href="https://buymeacoffee.com/tomaszhabiq">support</a> toward those costs.

If macOS prevents you from running the app and displays a warning that it may be malware, this is due to the lack of notarization described above. To bypass this restriction, please follow [these instructions](https://wiki.hacks.guide/wiki/Open_unsigned_applications_on_macOS_Sequoia_and_newer).

## Ownership, Copyright, and License

This project, including all original source code, documentation, and related materials, is copyrighted by Tomasz Habiger. This software is licensed under the PolyForm Noncommercial License. See the LICENSE file for details.

## Attribution

Please retain all copyright notices, license notices, and attribution to the original author in any redistribution or derivative work.

## Contributing

Contributions are welcome and appreciated. By contributing to this project, you agree to the terms described in CONTRIBUTING.md.
