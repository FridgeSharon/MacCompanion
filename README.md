# Mac Companion

A free, **source-available, noncommercial** macOS menu-bar utility based on
[Mos by Caldis and contributors](https://github.com/Caldis/Mos).

It combines smooth mouse scrolling, thumb-button gestures, window layouts with space
for Stage Manager, and optional AWDL control in one application.

## License first

This is a modified Mos application, not an official Mos release. Its Mos-derived code
remains **CC BY-NC 4.0**. Public source does **not** grant permission to sell the app or
make the complete project OSI open source. The native gesture implementation also
contains adaptations under the custom Mac Mouse Fix license.

Read [LICENSING.md](LICENSING.md), [CREDITS.md](CREDITS.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before reuse or redistribution.
There is currently no downloadable application or automatic updater. A free ZIP download
would let people install the app without Xcode. The [binary-distribution review](BINARY_DISTRIBUTION.md)
records why the current app appears to meet Mac Mouse Fix's separate-work exception;
Developer ID signing, notarization and release validation are still pending.

## Features

- Mouse-only reverse/smooth scrolling and Mos's per-application scrolling exceptions.
- Hold one configured thumb button and move up/down/left/right. Short presses keep their
  ordinary click; action gestures fire once per hold.
- Experimental continuous desktop, Mission Control and App Exposé gestures on macOS 27.
  Other supported systems/actions use the discrete action backend.
- Direct Fill/Restore, halves and quarters, using title-bar double-clicks or edge drags.
- A configurable Stage Manager gap calculated before direct window placement.
- Optional AWDL on/off or automatic control for a foreground game on Wi-Fi, using a
  narrowly scoped, separately approved privileged helper.

### Mouse support and publication scope

Mouse input uses ordinary macOS/Quartz events. Logitech gaming mice can use their
normal Back/Forward thumb-button events for gestures. Keep G HUB for DPI, haptics,
firmware and other hardware configuration.

**This public snapshot omits Mos's vendor-specific HID++ backend**, its device catalogues,
hardware debug panel and vendor-only button aliases/actions. The inherited backend
included Solaar-derived material that was not cleared for combination with the
noncommercial application license. It has been excluded as a whole, rather than
removing credit or pretending that the same code is newly licensed.

Native mouse buttons, scrolling, gestures, layouts and AWDL remain in the source. A mouse
button exposed only through a vendor protocol is unsupported in this snapshot; configure
it to generate a normal mouse event in the vendor utility where possible. Existing
vendor-only bindings from stock Mos may need to be recorded again as native buttons.

## Build from source

Requirements: macOS 13 or later, full Xcode with its macOS SDK, Python 3, and your own
Apple Development signing identity. The continuous gesture bridge is currently gated
to macOS 27 and uses private APIs that can change.

```sh
git clone https://github.com/FridgeSharon/MacCompanion.git
cd MacCompanion
export COMPANION_TEAM=ABCDE12345
./scripts/build.sh build
```

Use your actual Apple Developer Team ID instead of the example. The script creates
`.build/Source`, replaces the explicit signing-team placeholder in both XPC peers and
the Xcode project, then builds there. The reviewed public source stays unchanged.
Open the generated project in `.build/Source` if you prefer Xcode's editor.

The generated app is under `.build/DerivedData/Build/Products/Debug/`. Install it in a
stable location and approve Accessibility before using input/window features. Approve
the optional AWDL helper separately in macOS Login Items & Extensions if needed.
Do not run overlapping scrolling/window controllers at the same time.

```sh
# Quit Mac Companion before running signed tests.
./scripts/build.sh test

# Compile only, without signing or launching an app:
./scripts/build.sh check
```

`check` compiles the app and test target. It does not start an unsigned test host or
grant permissions. No signing keys, certificates or prebuilt application are included.
The public bundle identifier differs from the original private installation.

## Behavior and limitations

Direct sizing temporarily owns matching macOS title-bar and edge-drag preferences. It
restores recorded values when stopped; crash recovery runs on the next launch. Floating
restore history is in memory. Option-clicking the green button remains native and can
need corrective resizing. Some windows enforce minimum sizes or reject Accessibility
resizing. Full-screen, dialog, offstage and excluded windows are skipped.

AWDL suppression interrupts AirDrop/Continuity while active. The helper changes only
`awdl0`; quitting or losing the app connection restores it. Game detection checks the
foreground app's declared game category/Game Mode support and Wi-Fi, and does not infer
games inside arbitrary VMs or streaming clients.

This is a development source snapshot. Its public native-input variant has its own
validation record in [VALIDATION.md](VALIDATION.md); do not treat private-build device
results as acceptance of every public configuration.

## Credits

Mos — Caldis and contributors; Mac Mouse Fix — Noah Nuebling; Rectangle — Ryan Hanson
and Spectacle/Eric Czarny; AWDLControl — James Howard; Charts — Daniel Cohen Gindi and
Philipp Jahoda; LoginServiceKit — Clipy Project. Mac Companion integration and public
source preparation — Guy Sharon.

Full scope, license texts and modification notices are linked in [CREDITS.md](CREDITS.md)
and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No upstream endorsement is implied.
