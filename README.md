# Mac Companion

One macOS menu-bar app for smooth scrolling, mouse gestures, window layouts,
trackpad middle-click and AWDL control. Based on [Mos](https://github.com/Caldis/Mos).

**Free for noncommercial use · Source-available · macOS 13+**

## Download and setup

[**Download 0.1.0 beta**](https://github.com/FridgeSharon/MacCompanion/releases/download/v0.1.0-beta.20261102.1/MacCompanion-0.1.0-beta-20261102.1-universal.zip)
— build 20261102.1, signed and notarized for Apple Silicon and Intel.

1. Unzip and move **Mac Companion.app** to Applications. Quit the previous version before replacing it.
2. Open the app and approve **Accessibility** for scrolling, gestures and window controls.
3. Open **Preferences** from the menu bar to configure each feature and launch at login.

Optional AWDL control needs separate helper approval in **Login Items & Extensions**.
Quit overlapping scrolling/window utilities before use. Updates are manual; Xcode is not needed.

[Release notes](https://github.com/FridgeSharon/MacCompanion/releases/tag/v0.1.0-beta.20261102.1)
· [SHA-256 checksum](https://github.com/FridgeSharon/MacCompanion/releases/download/v0.1.0-beta.20261102.1/MacCompanion-0.1.0-beta-20261102.1-SHA256.txt)

## Features

| Feature | What it does |
| --- | --- |
| Scrolling | Mouse-only inversion, smooth scrolling, tuning and per-app exceptions |
| Mouse gestures | Hold one chosen thumb button and move to open Mission Control, App Exposé or switch desktops; short presses keep their normal click |
| Window layouts | Fill, Restore, halves and quarters, with configurable space for Stage Manager |
| Trackpad middle-click | Three-finger tap or physical click, including held middle-button dragging |
| AWDL | Manual on/off or automatic control for a foreground game on Wi-Fi |

## Compatibility and limits

- **Mice:** standard macOS button events are supported. Keep G HUB for Logitech DPI,
  firmware and other hardware settings; vendor-only buttons are unsupported.
- **Gestures:** continuous transitions use private APIs, are experimental and limited to macOS 27.
  Other supported systems/actions use discrete gestures.
- **Trackpads:** experimental private APIs on macOS 13–27. Native three-finger Look Up/drag can
  conflict. After reconnecting an external trackpad, toggle middle-click if needed.
  Magic Mouse gestures are unsupported.
- **Windows:** direct sizing handles title-bar double-clicks and edge drags. It temporarily
  changes matching macOS controls and restores them when stopped or during crash recovery.
  Some windows reject resizing; Option-clicking the green button stays native and may need correction.
- **AWDL:** suppression interrupts AirDrop/Continuity. Automatic detection uses the foreground
  app's declared game status; it does not detect games inside arbitrary VMs or streaming clients.

This is a beta. Physical Intel testing and fresh-Mac helper installation remain unverified.
See [validation](VALIDATION.md) and the [quality review](QUALITY.md) for tested behavior and known issues.

## Build from source

Requires full Xcode, Python 3 and your own Apple Development signing identity.
Replace the example with your 10-character Team ID:

```sh
git clone https://github.com/FridgeSharon/MacCompanion.git
cd MacCompanion
export COMPANION_TEAM=ABCDE12345
./scripts/build.sh build
```

The generated app is in `.build/DerivedData/Build/Products/Debug/`.
Use `./scripts/build.sh check` to compile without signing or launching;
use `./scripts/build.sh test` for signed tests after quitting Mac Companion.
See [RELEASING.md](RELEASING.md) for packaging and notarization.

## License

Mac Companion is an independent Mos derivative under **CC BY-NC 4.0**, with separate
component terms including the custom Mac Mouse Fix license. The combined app **cannot
be sold under its current licenses** and is **not OSI open source**.

Read [licensing](LICENSING.md), the [binary-distribution review](BINARY_DISTRIBUTION.md)
and [third-party notices](THIRD_PARTY_NOTICES.md) before reuse or redistribution.
The download includes full license texts. Mos's vendor HID++ backend and Solaar-derived
catalogues are excluded from this public version.

## Credits

| Project | Original authors |
| --- | --- |
| [Mos](https://github.com/Caldis/Mos) | Caldis and contributors |
| [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) | Noah Nuebling |
| [Rectangle](https://github.com/rxhanson/Rectangle) | Ryan Hanson |
| [Spectacle](https://github.com/eczarny/spectacle) | Eric Czarny |
| [AWDLControl](https://github.com/james-howard/AWDLControl) | James Howard |
| [Charts](https://github.com/ChartsOrg/Charts) (historical dependency) | Daniel Cohen Gindi and Philipp Jahoda |
| [LoginServiceKit](https://github.com/Clipy/LoginServiceKit) | Clipy Project |

Integration, independent trackpad middle-click and original additions: **Guy Sharon**.
[Middle by Ryan Hanson](https://github.com/rxhanson/Middle-Community) is a behavior reference;
no code or assets were copied. See [CREDITS.md](CREDITS.md) for contribution details.
No upstream endorsement is implied.
