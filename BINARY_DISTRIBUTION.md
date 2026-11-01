# Downloadable application review

Reviewed 2026-11-01 against public source commit
`08e85accb8295db129bb1faf34e25599f6734271`. No binary release has been published.

A **free, noncommercial** GitHub Release containing the compiled `.app` in a ZIP is a
viable distribution route. Users would unzip it, move it to Applications and approve
Accessibility; the optional AWDL helper requires separate macOS approval. Users do not
need Xcode or a developer account. The publisher needs signing and notarization setup.

## Mac Mouse Fix: compiled-distribution assessment

The relevant [MMF License](https://github.com/noah-nuebling/mac-mouse-fix/blob/2dae68a01ebcb4c645161160a7872a60ecf58ace/License)
was checked at the referenced revision and current `master`. Both have the same license
blob, `cd1dc685454c8872483083bb40894be6a4ad7dd1`.

The license requires apparent derivation credit for published work and prohibits malware
or hidden malicious content in compiled distributions. Its further condition ordinarily
requires preserving MMF's active licensing, trial and payment systems. Merely offering
a binary free of charge does not remove that condition.

The license expressly excepts a substantially improved or extended work that should be
considered a separate derivative. Our assessment is that **this specific Mac Companion
implementation fits that exception**:

- It is a distinct Mos-based application, not a repackaged MMF app or a bypass of MMF's
  trial/payment system. No MMF app bundle, updater, payment assets or trial state is used.
- MMF-derived work is limited to the native gesture protocol/bridge and continuous
  gesture scaling in `NativeGestureBridge.*` and `ContinuousGestures.swift`.
- The resulting application adds/integrates substantial separate functionality:
  Mos scrolling and app exceptions, configurable gesture recognition, direct window
  Fill/Restore/tiling with Stage Manager reservation, and AWDL policy with a scoped helper.
- The author's explanatory notes expressly describe allowing reuse in other projects
  and free distribution of substantial improvements. Those notes support this reading;
  the operative exception, rather than those notes alone, is its basis.

This is a documented interpretation of the published license, **not an author-specific
permission or legal determination**. There is no separate approval from Noah Nuebling,
and none is claimed. If the codebase changes into a close MMF fork, revisit this analysis.
The KingIsulgard polynomial-regression code mentioned in MMF's license notes is not
included here; the MMF author's personal permission is not transferable to this project.

No MMF payment/trial system needs to be added under the above interpretation. Mos's
independent CC BY-NC restriction still prevents selling the complete combined app.

## Attribution in the download

Keep the complete MMF license, Noah Nuebling's copyright and clear modification/derivation
credit. The current compiled development app was inspected: its `MacMouseFix-LICENSE.txt`
is byte-for-byte identical to `LICENSES/MacMouseFix.txt`, and its bundled
`ThirdPartyNotices.txt` names MMF, Noah Nuebling and the referenced commit.

The same inspection confirmed exact bundled copies of the CC BY-NC, Rectangle,
AWDLControl, Charts and LoginServiceKit license texts. The production artifact must be
checked again after building; verification of a development bundle is not release approval.

Include an accessible installation/credits text alongside the app in the ZIP, plus the
full license texts. The GitHub Release description must state the following in clear
language (links may use the corresponding upstream project URLs):

> Mac Companion is an independent, noncommercial modification of Mos by Caldis and
> contributors. Its native gestures include code adapted from Mac Mouse Fix by Noah
> Nuebling under the MMF License. Window handling also draws on Rectangle/Spectacle;
> AWDL control draws on AWDLControl. Charts and LoginServiceKit are dependencies.
> Full credits, modifications and license texts are included. No upstream endorsement
> is implied. The complete combined application may not be sold under its current terms.

Retain all [component notices](THIRD_PARTY_NOTICES.md) and [modification credits](CREDITS.md).
Do not describe the complete app as MIT/GPL or unrestricted open source. The excluded
Solaar-derived/vendor HID++ backend must remain absent from the public build.

## Signing and release readiness

The initial review found only an Apple Development identity. With the owner's approval,
a **Developer ID Application** identity has now been created and installed in Keychain.
An exported Release build, version `0.1.0` / build `20261101.2`, contains both Apple
Silicon and Intel code in the app and helper. Its licenses, credits, signing identity,
hardened runtime, secure timestamps and absence of debugging entitlements were verified.
Apple notarization is pending; this is not yet an approved public download.

See [RELEASING.md](RELEASING.md) for the reproducible release process and verification
script. The existing development app is not used as the public release artifact.

For a normal GitHub installation, use a Developer ID Application certificate, hardened
runtime, a secure timestamp, and Apple notarization with the ticket stapled to the app.
Apple documents [Developer ID distribution](https://developer.apple.com/developer-id/)
and [command-line notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
A ZIP does not require a Developer ID Installer certificate.

Before publishing the actual artifact:

1. Build the public source with a unique release build number. Both XPC peers must use
   the publisher's same signing team and the public app/helper identifiers. Keep signing
   keys and notarization credentials outside Git. Do not weaken the helper's signature
   requirements to accommodate an unsigned download.
2. Verify the Release app, helper and embedded code signatures, hardened runtime and
   absence of debugging entitlements. Confirm the minimum OS and actual architectures
   from the built executables; do not claim universal support from an arm64-only build.
3. Verify licenses and attribution in that exact bundle. Create the ZIP with the app,
   installation/credits text and license copies, retaining signatures and excluding
   AppleDouble metadata. Record the source commit, app version/build and SHA-256 checksum.
4. Obtain an accepted notarization result, staple and validate its ticket, and verify
   Gatekeeper acceptance. Verify the final ZIP after extraction as well.
5. Validate the public variant's scrolling, thumb buttons, layouts and optional helper
   separately from the private app. Installation on another Mac should be tested before
   describing the download as stable. Mark an initial release as a prerelease until then.

Source compilation previously passed 133 tests. That is not evidence of a notarized
download or a fresh installation. The private installed app and its settings are separate
and have not been changed for this review.
