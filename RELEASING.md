# Preparing a GitHub download

Read [BINARY_DISTRIBUTION.md](BINARY_DISTRIBUTION.md) before compiling for redistribution.
Distribution is free and noncommercial. Preserve all credits and component licenses.
There is no Sparkle/appcast or automated publishing path in this fork.

## Credentials

Use a Developer ID Application identity in the macOS Keychain. The same team must sign
the app and AWDL helper. `COMPANION_TEAM` configures both XPC peers through
`scripts/prepare.py`; do not edit only one peer. `COMPANION_IDENTITY` is the identity
name reported by `security find-identity -v -p codesigning`.

Notarization can use an existing team API profile with the `asc` CLI, or a properly
configured `notarytool` Keychain profile. Neither a private key nor a credential export
belongs in this repository. Do not revoke unrelated certificates or weaken helper
authentication as part of release preparation.

## Archive and export

Set both `CURRENT_PROJECT_VERSION` entries to a new `YYYYMMDD.N` value before building;
commit the version and record the source commit in the release notes. The initial
marketing version is `0.1.0`; use a prerelease tag while public-device testing is pending.

```sh
python3 scripts/audit_export.py
python3 scripts/prepare.py --team "$COMPANION_TEAM"
xcodebuild archive -project .build/Source/Mos.xcodeproj -scheme Debug \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath .build/Release/MacCompanion.xcarchive \
  -derivedDataPath .build/ReleaseDerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$COMPANION_TEAM" \
  CODE_SIGN_IDENTITY="$COMPANION_IDENTITY" \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO OTHER_CODE_SIGN_FLAGS=--timestamp
```

Use `xcodebuild -exportArchive` with a private local ExportOptions plist containing
`method=developer-id`, `signingStyle=manual`, your `teamID` and `signingCertificate`.
Do not pass a conditional build-setting key containing `=` on the command line; the
global identity override is sufficient. Do not launch an unsigned build or replace a
private installation to test archive creation.

## Notarize, staple and package

Run `scripts/verify_release.py APP_PATH --team "$COMPANION_TEAM" --before-notarization`
against the exported app. This checks licenses, MMF attribution, both architectures,
app/helper identity, matching embedded XPC peer requirements, hardened runtime,
timestamps and absence of debugging entitlements.

Create a submission ZIP with `ditto -c -k --keepParent APP_PATH SUBMISSION.zip`, then
submit with `asc --profile YOUR_PROFILE notarization submit --file SUBMISSION.zip`.
Wait for **Accepted** using the returned submission ID, and inspect its log if rejected.
Use `xcrun stapler staple APP_PATH`, then run the verification script again without
`--before-notarization`; the final check also requires a valid ticket and Gatekeeper
acceptance. `asc` reuses its Keychain-backed API profile; no second API key is needed.

The download ZIP must contain the stapled app, installation/credits text, and the full
LICENSES directory. Use `ditto -c -k --norsrc --noextattr --keepParent` on the staging
folder to avoid AppleDouble entries. Check its contents, extract into a fresh directory,
rerun the full verification on the extracted app, and publish a SHA-256 checksum.

Release notes must include the clear derivation credit in BINARY_DISTRIBUTION.md, source
commit, version/build, architectures, minimum macOS version, installation/permission
steps, and known limitations. Continuous gestures are currently gated to macOS 27;
other supported systems use action gestures. Do not describe Intel compilation as
physical Intel testing, or the private app's acceptance as public-build acceptance.

Prepare a GitHub prerelease draft with the verified ZIP, checksum and release notes.
Review the actual assets and target commit before publication. Signing and notarization
are artifact checks, not proof that every device configuration has been tested.
