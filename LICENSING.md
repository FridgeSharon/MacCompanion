# Licensing and distribution

Reviewed 2026-11-02. This project publishes public source and a **free, noncommercial**
compiled GitHub prerelease. See [the binary-distribution review](BINARY_DISTRIBUTION.md)
for the Mac Mouse Fix assessment and artifact-verification requirements. There is no
paid license, subscription or automatic updater.

## Can this app be sold?

**No, under the current permissions.** The application is derived from Mos, whose
[CC BY-NC 4.0 license](https://creativecommons.org/licenses/by-nc/4.0/legalcode.en)
permits noncommercial sharing and adaptation with attribution/change notices. Neither
giving credit nor publishing the code removes its noncommercial restriction.

Commercial use needs additional permission from the applicable rightsholders or
replacement of the restricted code/assets. This repository makes no commercial-license
grant for third-party material. Monetization through a different payment label is not
treated as a workaround.

## Public source versus open source

The source is public and may be inspected, built and modified within its licenses.
Because noncommercial and custom-license conditions remain, the complete project is
**not OSI open source**. The [Open Source Definition](https://opensource.org/osd) permits
commercial redistribution. GPL itself allows selling; it cannot be applied by us to
remove another author's noncommercial conditions.

The default terms for Mos-derived code and our original additions are CC BY-NC 4.0.
Separately identified third-party portions keep their own terms. MIT/Apache components
are not stripped of their original permissions by this notice, and their licenses do
not make the complete combined application commercially reusable.

## What changed to make this public snapshot possible?

The private fork inherited a vendor-specific Logitech HID++ backend, including two
catalogues explicitly derived from Solaar GPL-2.0-or-later files. Rather than assume
those files can be combined under a noncommercial application license, this snapshot
excludes **the entire `Mos/Logi` and `Mos/Integration` implementation**, the vendor
button-alias implementation and the related device tests. Those files are absent from
both the exported tree and its new Git history. Ordinary Quartz mouse/keyboard input
remains; there is no vendor protocol implementation behind the compatibility adapter.

The omission is not a declaration that upstream authors infringed a license, or that
all factual protocol data is copyrightable. It is a conservative boundary for this
publication. Do not copy the excluded backend back in without a fresh license review.
The installed private app is separate and was not changed by this source publication.

## Mac Mouse Fix conditions

The native continuous-gesture files contain adaptations under the
[custom MMF License](LICENSES/MacMouseFix.txt). They are credited explicitly to Noah
Nuebling. The license permits source sharing with derivation credit; its conditions
for publishing a compiled application are separate, including an exception for a
substantially improved/separate derivative work.

For the current Mac Companion implementation, our assessment is that the separate-work
exception applies: a limited gesture adaptation is integrated into a distinct Mos-based
app with scrolling, direct window layouts, Stage Manager reservation and AWDL control.
This is an interpretation of the published license, not separate permission or an
endorsement from the MMF author. The reasoning, required release attribution and exact
scope are recorded in [BINARY_DISTRIBUTION.md](BINARY_DISTRIBUTION.md). Do not assume the
same conclusion for an MMF clone, a different combination or a future redistribution.
A free binary alone is not automatically exempt from the MMF conditions.
The separate polynomial-regression component mentioned in MMF's license notes is not
included here; its author's personal permission is not asserted as ours.

## Notices and trademarks

See [CREDITS.md](CREDITS.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and the
verbatim texts in [LICENSES](LICENSES). Keep original copyright/license notices and
identify modifications when redistributing source. Preserve applicable Apache NOTICE
content when a dependency supplies it. Do not imply upstream endorsement.

Apple SDKs/frameworks are obtained through Xcode and are not redistributed here. Apple
SF Symbol resources and other third-party marks remain subject to their own terms;
our default source license is not an independent license for those graphics or marks.
See [Apple's SF Symbols documentation](https://developer.apple.com/sf-symbols/) and
[custom symbol distribution guidance](https://developer.apple.com/documentation/technologyoverviews/annotating-sf-symbols).

This inventory is not a promise that every proposed future distribution/business model
is authorized. New dependencies, assets, binary releases or monetization need review
against their actual licenses.
