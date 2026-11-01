# Mac Companion public source

This is a source-available, noncommercial Mos-derived application. Read README.md,
LICENSING.md and THIRD_PARTY_NOTICES.md before modifying or distributing it.
Keep upstream attribution and per-component licenses. Do not relabel the tree as MIT/GPL.
The vendor-specific Logitech backend and Solaar-derived catalogues are absent;
mouse input uses ordinary macOS events and hardware settings remain with vendor tools.
Do not import those excluded files without a new licensing review.

Use scripts/build.sh and your own signing team. Build/test output stays in .build/.
Never run an unsigned test host with a live input-handler app. No certificates, keys,
preferences, device captures, local diagnostics or compiled app bundles may be committed.
App source is synchronized from Mos/ in Xcode; tests are explicit project members.
No automatic binary release or updater is configured.
