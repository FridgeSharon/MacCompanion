# Maintenance and performance review — 2026-11-19

Reviewed the public source at `25bdead` on macOS 27.2.1, Apple Silicon.
The findings below distinguish measurements of the installed private build from
tests of the local maintenance candidate.

| Finding | Change and evidence |
| --- | --- |
| Scroll input could be swallowed when the display link or event route was unavailable. A change of target could carry buffered movement into another app. | Preserve native passthrough on failure and finish the old target's sequence before accepting the new target. An isolated event sink verifies both recipients, phases and deltas. |
| A display-link callback could stop the link it was running on. | Schedule completion on the main run loop, check the input sequence before stopping, and clean up partially installed event taps. The simulator exercises the phase transitions without posting to desktop apps. |
| Waking the Mac and activating the user session independently restarted input handlers. | Resume once both conditions hold. The regression suite covers both notification orders and duplicate notifications. |
| Stage Manager repeatedly decoded the same WindowServer snapshot and queried directly managed windows. | Index layer-zero frames by process once per pass and skip managed windows before Accessibility queries. In an optimized synthetic fixture of 12 processes and 120 windows, 40 passes returned the same 4,800 matches. Two runs took 25–31 ms before and 1.8–2.3 ms after. These timings cover only frame lookup. |
| Ordinary clicks could query the foreground app and exclusions before middle-click eligibility was known. | Check the device and recent three-finger state first. Held clicks still follow their source device through release. |
| The source audit could pass with a missing bundled license. | Share the release verifier's six-file mapping, require every copy, and compare bytes. All 12 missing-file or altered-file fixtures were rejected. The audit now skips build and Git directories before traversing them. |

**Candidate verification.** All 154 signed tests passed normally and under Thread
Sanitizer. The unsigned optimized app and helper both compiled for arm64 and x86_64.
Clang static analysis passed for the helper and both native input bridges.

**Installed app sample.** Over 60.06 seconds of ordinary background operation with
private build `20261101.7`, the app consumed 0.48 seconds of CPU (0.80% of one
core). RSS ranged from 107,136 to 107,152 KiB. The AWDL helper used 0.01 seconds
of CPU and 7,472–7,504 KiB RSS. A separate heap scan reported two leaked
allocations totaling 368 bytes rooted in an XPC rich-error object. Attribution
to a specific caller and long-term growth remain unverified. The original app
was reopened after the signed tests.

**Remaining coverage.** The signed suite runs with startup input handlers disabled.
Fresh physical wheel/trackpad handoff, display reconnect, Intel execution and a
long-duration soak of this candidate remain outstanding. In particular, synthetic
pixel-scroll events still carry legacy delta fields from their template; consumers
that read multiple delta representations need real-app compatibility testing.

[Source provenance and licensing assessment](PROVENANCE.md)

# Code quality review — 2026-11-01

This pass hardens the existing application. It adds no user-facing features and does
not replace the published beta download. The reviewed application source is commit
`ec8f955247c1df4afa92d8fcb1d1d496f46f5438` (local build `20261101.7`).

## Changes

- Bound title-bar inspection and drag work to one pending job each, preventing an
  unresponsive Accessibility server from accumulating high-frequency input jobs.
- Validate the complete native-window preference journal before either claiming
  ownership or restoring settings. Reject missing, duplicate, foreign or incorrectly
  typed entries without writing system preferences or discarding recovery data.
- Serialize trackpad frame delivery with handler removal and device-registry updates.
  Keep the existing source-device checks and balance middle-button release on stop.
- Reject stale network-monitor and XPC callbacks after AWDL controller shutdown or
  reconnection. Automatic suppression now independently tracks sleep and user-session
  activity; manual AWDL modes retain their existing behavior.
- Persist injected settings to their intended preferences store, invalidate an old
  interceptor timer before replacement, and remove recursive popover layout calls.
- Replace deprecated application APIs and remove an unused archive utility and an
  unreachable storyboard scene. Preserve component licenses and modification notices.

## Verification

- **150 tests passed, zero failures**, including nine new cases for malformed journals,
  sleep/session ordering, isolated settings persistence, bounded Accessibility work
  and popover layout. A stalled-work test rejects 10,000 extra submissions and confirms
  that subsequent work is accepted once the pending job finishes.
- The same **150 tests passed with Thread Sanitizer**, with no race diagnostics.
  Startup input handlers are disabled under XCTest; this does not establish race-free
  behavior for every physical-device callback.
- Compile-only app/test build and optimized universal application build passed.
  Clang's static analyzer reported no findings for the privileged helper or native
  gesture/trackpad bridges. Source-export licensing/privacy and whitespace checks passed.
- The owner tested mouse scrolling, four thumb gestures, Fill/Restore/snapping and
  three-finger physical middle click in the updated local build and reported success.
  The middle-click feature also stopped and restarted correctly through Preferences.
- The local update retained the installed app's signing requirement and preferences.
  Graceful shutdown cleared its window-preference lease; AWDL reconnected in the
  existing automatic mode after restart. The prior app remains available for rollback.

## Runtime observations and limits

On macOS 27.0.1 with the optimized Apple Development-signed local build, a 90-second
mixed-use/inspection interval consumed 1.10 seconds of application CPU time, about
**1.2% of one core**. The helper consumed no measurable CPU time at the counters'
resolution. A fresh background-only baseline is recorded separately from heap scans,
which substantially perturb resident-memory readings.

Across 60 seconds after a clean restart with Preferences closed, the app consumed
0.29 seconds of CPU time (**0.48% of one core**); RSS remained exactly 60,768 KiB
(about **59 MiB**) at every sample. The subsequent five-second stack sample showed
a **17.3 MB physical footprint** and a waiting main event loop. The helper stayed at
9,680–9,728 KiB RSS with no measurable CPU-time increase.

Heap scans reported 2,192 bytes initially and 10,592 bytes after repeated Preferences
accessibility inspection, tab changes and closing the window. Reported roots were
AppKit `NSAccessibilityCustomAction`/toolbar blocks and an XPC rich-error object;
no app-defined root types were reported. These framework-attributed findings are
retained as a limitation, not described as zero leaks. This is a short observation,
not a long-duration soak or a guarantee against retained-but-reachable objects.

The debugger localized the remaining layout-reentrancy warning to AppKit's
`NSStatusItem` scene/frame layout on this OS. That stack had no application layout
callback. The Preferences regression test still passed. AppKit's inherited table
column-selection warning, SDK XCTest deployment-target warnings and skipped
AppIntents metadata extraction also remain documented diagnostics.

Physical acceptance across Intel Macs, other OS versions, fast user switching,
every sleep/wake order and every network/display configuration remains incomplete.
Continuous gestures and trackpad touch interfaces still depend on private macOS APIs.

## Ongoing checks

The source-quality workflow runs export/privacy checks, an unsigned compile-only
app/test build and native static analysis for pull requests and pushes to `main`.
It has read-only repository permissions, a commit-pinned checkout action, no signing
secrets and no app launch or binary publication. Signed tests and physical-device
acceptance remain local checks using the documented build script.
