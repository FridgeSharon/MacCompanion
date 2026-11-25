# Source provenance

This inventory covers the public Mac Companion source at commit
`25bdead3bbe6b2591ff142571251bd9a73afef69` and compares it with the Mos base
`8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2`. The public Git history begins with
`08e85accb8295db129bb1faf34e25599f6734271`, an export of the modified source.
The new Git root changes the history visible to readers. The inherited code and
resources remain visible in the tree comparison. [Mac Companion baseline][public]
· [Mos base][mos] · [First public snapshot][initial]

The complete application remains a noncommercial Mos derivative. This inventory
records lineage and review boundaries under the published terms. The license
texts, component attribution and distribution assessment live in
[LICENSING.md](LICENSING.md), [CREDITS.md](CREDITS.md),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[BINARY_DISTRIBUTION.md](BINARY_DISTRIBUTION.md).
[Mos license at the source revision][mos-license] · [CC BY-NC 4.0 legal code][cc]

## Evidence from the pinned Git trees

The Mos base contains 690 tracked paths. Each public path falls in one of the
following four comparison categories. “Same path, changed” records a path
match with different bytes. The license, README and agent instructions,
for example, were replaced at their existing paths. “New path and blob” records
the absence of a same-path or exact-content match. It includes adaptations,
original additions, and copies of other projects' notices.

| Public snapshot | Same path, exact bytes | Same path, changed bytes | Other Mos path, exact bytes | New path and blob | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| First public export | 170 | 18 | 0 | 41 | 229 |
| Reviewed public baseline | 87 | 26 | 1 | 59 | 173 |
| Reviewed baseline, Swift and Objective-C source and headers | 32 | 15 | 1 | 25 | 73 |

The 173-path baseline contains 121 unchanged paths from the first public export,
33 changed paths and 19 paths added since that export. The first export had 75
paths later removed. The reduction includes the lean-build changes in
[`bb14022`][trim]. Files are counted once by path. The 73-file code count
covers `.swift`, `.m` and `.h`, including tests. It excludes the storyboard,
localizations, assets, project configuration, license files and build scripts.

| Public baseline scope | Same path, exact bytes | Same path, changed bytes | Other Mos path, exact bytes | New path and blob |
| --- | ---: | ---: | ---: | ---: |
| `Mos/` application code and resources | 79 | 18 | 1 | 37 |
| `MosTests/` | 4 | 1 | 0 | 1 |
| `Mos.xcodeproj/` | 4 | 3 | 0 | 0 |
| `AWDLHelper/` | 0 | 0 | 0 | 2 |
| Everything else | 0 | 4 | 0 | 19 |

### Mos code and resources

- `Mos/ScrollCore/` retains the engine. Six of its eight files are byte-for-byte
  Mos, including the interpolator, filter and dispatch context. `ScrollCore.swift`
  and `ScrollPoster.swift` contain local changes. Input and settings are also
  mixed. Examples include unchanged `InputEvent.swift` and key handling files
  alongside modified `Options.swift` and `Interceptor.swift`.
- `Mos/Options/LegacyInputModels.swift` is exact Mos content under a different
  path. It matches `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`
  at blob `efd18ab9c2bf574b004e448b593b57bf86d89e0b`. The lean-build commit
  relocated it. [Mos file][mos-model] · [Relocation commit][trim]
- `Mos/NativeInput/NativeHardwareCompatibility.swift` is local shim code for
  retained Mos callers. It carries a local copyright header and preserves
  upstream names and API shapes, including `LogiCenter`, `ScrollRole` and
  `LogiStandardMouseButtonAlias`. Its vendor-facing methods return inert
  defaults. Treat the shim and its callers as inherited-app integration when
  evaluating reuse. [Shim in the public baseline][shim]
- Startup, menu, preferences, shortcuts, the Xcode project, storyboard and
  localization catalogs include retained and adapted Mos content. The new
  Companion PNG icon set is documented as generated for this project. The
  unchanged Mos asset catalog entries include inherited artwork and Apple
  symbols. A future product needs its own rights review for reused assets.
- Mos credits Smoothscroll for websites in its upstream README. The comparison
  establishes Mos as the direct source for the retained scrolling files.
  The exact scope of earlier Smoothscroll influence is unverified here.
  Keep that credit for the inherited implementation. [Mos credits at the base][mos-readme]

### Other source and dependencies

| Public files or feature | Upstream evidence | Review boundary |
| --- | --- | --- |
| `Mos/Companion/NativeGestureBridge.h` and `.m` | Mac Mouse Fix revision `2dae68a01ebcb4c645161160a7872a60ecf58ace`, `Helper/Core/Touch/TouchSimulator.m` (blob `38a95e799fd3ceac0750244b365dd3f4b5519ed4`), shows the DockSwipe HID event, progress and velocity fields and phases. | Mac Companion uses its own bridge and a different event setter. Retain the MMF notice for the adapted subsystem. [MMF TouchSimulator][mmf-touch] |
| `Mos/Companion/ContinuousGestures.swift` | At the same MMF revision, `Helper/Core/Drag/ThreeFingerSwipe/ModifiedDragOutputThreeFingerSwipe.m` derives horizontal progress from display width and Space count, with the same `spaces <= 1 ? 2 : 1 + 1 / (spaces - 1)` limit. | Track the formula and scaling alongside the gesture bridge under the MMF review. For compiled distribution, see the documented assessment of the custom license's separate-work exception. [MMF scaling source][mmf-scale] · [MMF license][mmf-license] |
| `Mos/Companion/WindowAccessibility.swift` | Rectangle's `AccessibilityElement.swift` shows the size/position transaction and its Enhanced UI handling. The cited review snapshot is `39466aea1a6c942eb3bbdd4a7b5d6da8662106f5`, file blob `48e38f7b73c00b3274a17b6835f8723858c0de52`. | Keep Ryan Hanson and Spectacle/Eric Czarny attribution. The exact development reference revision is unrecorded. The snapshot corroborates the adaptation credited in source and documents. [Rectangle frame transaction][rectangle-code] · [Rectangle license][rectangle-license] |
| `Mos/Companion/AWDLController.swift`, `AWDLPreferencesViewController.swift`, `AWDLHelper/main.m` and helper launch configuration | AWDLControl revision `5e3de007559233cd529a9d83300d7cf9483efa1e` has the foreground game-category/Game Mode condition, Service Management and XPC architecture, and `awdl0` route monitoring and interface-flag changes. | Treat the whole AWDL integration as mixed local and MIT-derived work. This comparison corroborates the adaptation. The project does not record an exact development-time source pin. [AWDLControl app policy][awdl-app] · [AWDLControl helper][awdl-helper] · [AWDLControl license][awdl-license] |
| `TrackpadMiddleClick.swift`, `TrackpadTouchBridge.h` and `.m`, and `TrackpadPreferencesViewController.swift` | The lean-build commit adds these files and describes the recognizer as independent. Source headers credit a local implementation of Apple's MultitouchSupport interface. Credits identify Middle as a behavior reference. | Keep separate review of Apple private API usage and original authorship. Existing Git history and source statements document the project's provenance claim. They do not establish the contents of all possible external implementations. [Trackpad introduction][trim] · [Middle public project][middle] |
| Other `Mos/Companion/` logic and `MosTests/CompanionTests.swift` | The first public export includes the local gesture recognizer, button monitor, settings, Stage Manager and window layout, integrated UI and tests. Later Git history shows changes and additions to those features. | Treat new logic as local additions to the noncommercial app, subject to component review before extraction. Public Git begins after some original development. One unmatched blob cannot establish that the complete file is independent. [First public snapshot][initial] |
| LoginServiceKit | The Xcode SwiftPM lockfile pins version 2.4.0 at `5af9098805ff603830aec65754071c6514bbcacd`. | Active external Apache-2.0 dependency. Its pinned tree contains `LICENSE` and has no `NOTICE` entry. [LoginServiceKit license][login-license] |
| Charts / DGCharts | Version 5.1.0 at `dd9c72e3d7e751e769971092a6bd72d39198ae63`. The lean-build commit removed it from the package list. | Historical external Apache-2.0 dependency. Its pinned tree contains `LICENSE` and has no `NOTICE` entry. [Charts license][charts-license] · [Removal commit][trim] |

The [pinned Mos README][mos-readme] also acknowledges Sparkle and Solaar.
The current package lock contains only LoginServiceKit. The Mos
`LogiCIDDirectory.swift` and `LogiReceiverCatalog.swift` headers document
derivation from two Solaar sources at different revisions. The first cites
`lib/logitech_receiver/special_keys.py` at
`b9e0cf823543ba1dadc8eb188083b5c8db6280b0`. The second cites
`lib/logitech_receiver/base_usb.py` at
`ff9324d34693d6bb390c4dad4f5a0e731d2e9bd1`.
The comparison checked 46 pinned Mos paths under `Mos/Logi/`,
`Mos/Integration/`, the vendor button alias and named vendor test paths.
Their upstream blob IDs are absent from the reviewed public commit's full
reachable Git history. This is evidence about the audited paths and exact
blobs. The public native-input compatibility layer still retains vendor-named
API stubs. [Mos CID catalogue][mos-cid] · [Mos receiver catalogue][mos-receiver]
· [Solaar controls][solaar-controls] · [Solaar receivers][solaar-receivers]

### License text verification

The GitHub history of Mos's `LICENSE` up through the base records the file's
creation in 2017 at `086e63dd26dc400c4a9ed2eb0aac9136547d6c06` under CC BY-NC
4.0. The pinned source still carries that notice. That history provides no
earlier permissive Mos license for the audited snapshot.
[Mos license creation][mos-license-history] · [Pinned Mos notice][mos-license]

For the reviewed public commit, the six upstream files below were compared
with the license copies in `LICENSES/`. Each public copy has exactly one
additional LF byte at the end. The text is otherwise identical. The five
corresponding runtime copies are byte-for-byte equal to their public
`LICENSES/` copies. The sixth runtime copy is the full CC BY-NC legal text,
matching `LICENSES/CC-BY-NC-4.0.txt` within the public tree.

| Vendored notice at the reviewed baseline | Official upstream blob |
| --- | --- |
| `Mos-original-LICENSE.txt` | [`1d58de239124344c1008c342028a146ccdfcdd42`][mos-license] |
| `MacMouseFix.txt` | [`cd1dc685454c8872483083bb40894be6a4ad7dd1`][mmf-license] |
| `Rectangle-MIT.txt` | [`e54d4324dd661839eb1dec8d881ff7bb5cab8dd6`][rectangle-license] |
| `AWDLControl-MIT.txt` | [`f446cd29663007d46a73b6084b32ef0d0eb78f01`][awdl-license] |
| `Charts-Apache-2.0.txt` | [`8198c7a0cbb81aab113f5dd6f96dc6bf0dfb09a7`][charts-license] |
| `LoginServiceKit-Apache-2.0.txt` | [`5cd50e6d0223b948f6b004e82cc3da5cad9c3898`][login-license] |

## Routes to an independently distributable implementation

- **Keep the current fork.** Use the existing noncommercial distribution route
  with the component notices and the compiled MMF assessment. If commercial
  distribution of the fork is intended, obtain a written grant from the
  applicable rightsholders for the specific intended uses, including any MMF
  terms that still apply to the resulting binary.
- **Build a separate product.** Describe desired behavior as requirements and
  test observable results. Start in a new codebase with independently authored
  capture, scheduling and interpolation, settings and data models, UI, tests
  and assets. Remove inherited Mos glue and resources from that product's build.
  Omit or independently replace the MMF-derived native gestures unless their
  current terms or a separate written grant cover the intended release. Use
  independently documented Apple APIs where possible and assess the
  distribution implications of any private APIs separately.
- **Reuse components with documented rights.** The MIT portions of Rectangle
  and AWDLControl and the Apache-2.0 dependency can be considered under
  their own terms. Use their upstream versions or verify the lineage of
  each extracted file, keeping required notices and identifying changes.
  Separately review project-owned additions and underlying assets before
  choosing any new license. A fresh Git root and new names leave existing
  rights obligations in place.

### Practical migration sequence

1. Establish black-box acceptance cases using the current app. Include alternating mouse
   and trackpad input, two-axis wheels, inversion, per-app exceptions, switching foreground
   apps during momentum, wake/reconnect and idle CPU. Record expected behavior in new tests.
2. Prototype mouse-only scrolling in a separate target using Apple's Quartz event APIs
   and an independently designed smoothing curve. Compare feel on the physical mouse
   before moving settings or window controls. Run only one active input handler at a time.
   [Apple Core Graphics events](https://developer.apple.com/documentation/coregraphics/cgevent)
3. Replace the inherited app shell, settings UI, exception model, shortcuts, translations
   and resources. Test importing existing user preferences using disposable fixtures.
   Audit each local feature before moving it across. Rectangle and AWDLControl components
   can retain their permissive licenses and credits if third-party ownership is acceptable.
4. Decide how to deliver continuous gestures and trackpad middle-click. The current
   implementations use private APIs. An independent implementation still faces that
   distribution decision, particularly for the Mac App Store under guideline 2.5.1.
   [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
5. Verify the shipped product as well as the source tree. Inspect compiled inputs,
   resources, linked packages, bundled notices and contribution records. Select a
   software license once the rights to the remaining original contributions are clear.
   Earlier releases retain the licenses already granted. For a paid launch, obtain
   a rights review of the actual candidate and its distribution channel.

Copyright distinguishes functional requirements from the particular expression in
source, text and artwork. A behavior specification and new implementation give a
reviewer evidence of that distinction. A blob comparison alone cannot clear a
rewritten file. [U.S. Copyright Office guidance](https://www.copyright.gov/help/faq/faq-protect.html)

## Reproduce the path inventory

Run this with Python 3 and two read-only Git worktrees that contain the
commits. Set `MOS_REPO` to a Mos checkout and `PUBLIC_REPO` to a Mac Companion
checkout. Git object reads ignore working-tree edits. The comparison prints
all paths at the reviewed public baseline, including exact matches elsewhere
in the Mos tree. It also checks for the excluded vendor blobs in public
history. Rename detection, whitespace normalization and similarity heuristics
are excluded from the counts.

```sh
python3 - "$MOS_REPO" "$PUBLIC_REPO" <<'PY'
import subprocess
import sys
from collections import Counter, defaultdict

mos_repo, public_repo = sys.argv[1:]
mos_ref = "8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2"
initial_ref = "08e85accb8295db129bb1faf34e25599f6734271"
public_ref = "25bdead3bbe6b2591ff142571251bd9a73afef69"

def tree(repo, ref):
    output = subprocess.check_output(
        ["git", "-C", repo, "ls-tree", "-r", "-z", ref]
    ).decode()
    entries = (record.split("\t", 1) for record in output.split("\0") if record)
    return {path: metadata.split()[2] for metadata, path in entries}

mos = tree(mos_repo, mos_ref)
initial = tree(public_repo, initial_ref)
baseline = tree(public_repo, public_ref)
paths_for_blob = defaultdict(list)
for path, blob in mos.items():
    paths_for_blob[blob].append(path)

print("Mos paths", len(mos))
for ref, paths in ((initial_ref, initial), (public_ref, baseline)):
    totals = Counter()
    code_totals = Counter()
    for path, blob in paths.items():
        if mos.get(path) == blob:
            category = "same path, exact bytes"
        elif path in mos:
            category = "same path, changed bytes"
        elif blob in paths_for_blob:
            category = "other path, exact bytes"
        else:
            category = "new path and blob"
        totals[category] += 1
        if path.endswith((".swift", ".m", ".h")):
            code_totals[category] += 1
        if ref == public_ref:
            matches = ", ".join(paths_for_blob.get(blob, []))
            print(f"{category}\t{path}\t{matches}")
    print(ref, len(paths), dict(totals))
    print("Swift and Objective-C", sum(code_totals.values()), dict(code_totals))

shared = initial.keys() & baseline.keys()
print("Paths unchanged since first public export",
      sum(initial[path] == baseline[path] for path in shared))
print("Paths changed since first public export",
      sum(initial[path] != baseline[path] for path in shared))
print("Paths added since first public export", len(baseline.keys() - initial.keys()))
print("Paths removed since first public export", len(initial.keys() - baseline.keys()))

def excluded(path):
    return (
        path.startswith(("Mos/Logi/", "Mos/Integration/", "MosTests/Logi"))
        or path == "Mos/ButtonCore/LogiStandardMouseButtonAlias.swift"
        or (path.startswith("MosTests/") and "HID" in path)
    )

excluded_paths = {path: blob for path, blob in mos.items() if excluded(path)}
reachable = subprocess.check_output(
    ["git", "-C", public_repo, "rev-list", "--objects", "--no-object-names", public_ref],
    text=True,
).splitlines()
print("Excluded Mos paths", len(excluded_paths))
print("Excluded Mos blobs in public history", sorted(set(excluded_paths.values()) & set(reachable)))
PY
```

[public]: https://github.com/FridgeSharon/MacCompanion/tree/25bdead3bbe6b2591ff142571251bd9a73afef69
[initial]: https://github.com/FridgeSharon/MacCompanion/commit/08e85accb8295db129bb1faf34e25599f6734271
[trim]: https://github.com/FridgeSharon/MacCompanion/commit/bb1402256df17a4eada538c3d0b6727344f3ac63
[shim]: https://github.com/FridgeSharon/MacCompanion/blob/25bdead3bbe6b2591ff142571251bd9a73afef69/Mos/NativeInput/NativeHardwareCompatibility.swift
[mos]: https://github.com/Caldis/Mos/commit/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2
[mos-license]: https://github.com/Caldis/Mos/blob/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2/LICENSE
[mos-license-history]: https://github.com/Caldis/Mos/commit/086e63dd26dc400c4a9ed2eb0aac9136547d6c06
[mos-readme]: https://github.com/Caldis/Mos/blob/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2/README.md
[mos-model]: https://github.com/Caldis/Mos/blob/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2/Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift
[mos-cid]: https://github.com/Caldis/Mos/blob/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2/Mos/Logi/Core/LogiCIDDirectory.swift
[mos-receiver]: https://github.com/Caldis/Mos/blob/8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2/Mos/Logi/Core/LogiReceiverCatalog.swift
[cc]: https://creativecommons.org/licenses/by-nc/4.0/legalcode.en
[mmf-touch]: https://github.com/noah-nuebling/mac-mouse-fix/blob/2dae68a01ebcb4c645161160a7872a60ecf58ace/Helper/Core/Touch/TouchSimulator.m#L202-L238
[mmf-scale]: https://github.com/noah-nuebling/mac-mouse-fix/blob/2dae68a01ebcb4c645161160a7872a60ecf58ace/Helper/Core/Drag/ThreeFingerSwipe/ModifiedDragOutputThreeFingerSwipe.m#L41-L81
[mmf-license]: https://github.com/noah-nuebling/mac-mouse-fix/blob/2dae68a01ebcb4c645161160a7872a60ecf58ace/License
[rectangle-code]: https://github.com/rxhanson/Rectangle/blob/39466aea1a6c942eb3bbdd4a7b5d6da8662106f5/Rectangle/AccessibilityElement.swift#L157-L234
[rectangle-license]: https://github.com/rxhanson/Rectangle/blob/39466aea1a6c942eb3bbdd4a7b5d6da8662106f5/LICENSE
[awdl-app]: https://github.com/james-howard/AWDLControl/blob/5e3de007559233cd529a9d83300d7cf9483efa1e/AWDLControl/AppDelegate.m
[awdl-helper]: https://github.com/james-howard/AWDLControl/blob/5e3de007559233cd529a9d83300d7cf9483efa1e/AWDLControlHelper/AWDLMonitor.m
[awdl-license]: https://github.com/james-howard/AWDLControl/blob/5e3de007559233cd529a9d83300d7cf9483efa1e/LICENSE.txt
[charts-license]: https://github.com/ChartsOrg/Charts/blob/dd9c72e3d7e751e769971092a6bd72d39198ae63/LICENSE
[login-license]: https://github.com/Clipy/LoginServiceKit/blob/5af9098805ff603830aec65754071c6514bbcacd/LICENSE
[middle]: https://github.com/rxhanson/Middle-Community
[solaar-controls]: https://github.com/pwr-Solaar/Solaar/blob/b9e0cf823543ba1dadc8eb188083b5c8db6280b0/lib/logitech_receiver/special_keys.py
[solaar-receivers]: https://github.com/pwr-Solaar/Solaar/blob/ff9324d34693d6bb390c4dad4f5a0e731d2e9bd1/lib/logitech_receiver/base_usb.py
