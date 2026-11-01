# Public snapshot validation

Validated 2026-11-01 on macOS 27 with the installed Xcode macOS SDK.

- Application build: succeeded in an isolated build directory.
- `scripts/build.sh check`: application and test target compiled successfully without
  signing or launching unsigned code.
- `scripts/build.sh test`: **133 tests, 0 failures** using a locally configured signing
  identity. No signing identity or certificate is distributed in this repository.
- Tests cover gesture recognition/continuous phases, layout geometry, native preference
  recovery, window-history churn, scroll filtering/phases, idle display-link recovery,
  settings migration and preserving a native thumb binding without vendor discovery.
- `scripts/audit_export.py`: required licenses/notices present, excluded backend absent,
  matching runtime license copies, and source/export privacy gates passed.
- Shell/Python build helpers parsed successfully; Xcode project syntax validated.

This is the public **native-input source variant**. It excludes the vendor-specific HID++
backend and its tests; the private fork's larger test count is not claimed for this tree.
The public app was not installed over the original private app, and its bundle identifier
is separate. The installed private executable was checksum-verified unchanged after
validation and was restarted.

This test run does not establish physical acceptance of every public-build mouse,
display arrangement, macOS version, Wi-Fi/game combination or helper installation.
Continuous private-API gestures remain experimental. No public compiled release,
installer, notarization, updater or App Store submission is part of this publication.
