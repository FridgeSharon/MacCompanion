# Public build validation

Validated 2026-11-01 on macOS 27 with the installed Xcode macOS SDK.

- The lean application and its test target compile successfully.
- `scripts/build.sh test`: **141 tests, 0 failures**, using an Apple Development-signed
  test host with global app startup and input handlers disabled under XCTest.
- A real AppKit Preferences-window regression test cycles all seven tabs, requires
  all seven toolbar items to remain visible, and checks that the window frame stays
  unchanged. It also checks that non-scrolling labels and controls stay inside each
  pane. The final run reports no conflicting constraints or invalid storyboard
  tab relationships for this check.
- Gesture, layout, native preference recovery, scroll filtering/phases, idle
  display-link recovery and settings-migration checks remain covered. Eight focused
  trackpad tests cover tap rejection, source-device matching and balanced click release.
- The owner tested the Developer ID-signed lean build with physical devices and
  reported working three-finger tap, physical click/hold/drag, ordinary mouse clicks,
  mouse scrolling/inversion, four thumb gestures and title-bar Fill/Restore.
  This is owner-reported acceptance; browser counter telemetry was not independently
  verified. The subsequent Preferences-only fix has its own automated window check.
- A post-workload spot check of that lean build returned to 0.4% CPU. A five-second
  sample showed a 65.1 MB physical footprint and a waiting main event loop. This is
  a brief resource check, not a new comprehensive leak audit.
- `scripts/audit_export.py`: licenses/notices present, excluded backend absent,
  matching runtime license copies and source/export privacy gates passed.
- The universal app and helper pass Developer ID, hardened-runtime, secure-timestamp,
  entitlement and mutual XPC identity checks. No signing credentials are distributed.

The public app has a separate bundle identifier and has not overwritten the private
installation. The original private app and its settings are retained for rollback. A locally signed
build of the same corrected source was then installed using the existing private app
identity and signing requirement; its Middle Click and AWDL panes were visually checked.
Existing continuous-gesture/direct-sizing choices and AWDL automatic mode were preserved. The public
AWDL helper remains disabled during this validation; its installation, approval and
live network policy are not established by the private helper's earlier checks.

Physical acceptance on Intel, other macOS versions, other trackpads and every display
or Wi-Fi/game configuration remains unverified. Continuous gestures and trackpad touch
interfaces use private APIs and remain experimental. No automatic updater or App Store
submission is configured. Screenshots and GIF demos are deferred at the owner's request.
