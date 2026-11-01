#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-build}"
case "$mode" in build|test|check) ;; *) echo 'Usage: scripts/build.sh [build|test|check]' >&2; exit 2;; esac
if [[ "$mode" != check ]]; then
  if [[ ! "${COMPANION_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo 'Set COMPANION_TEAM to your 10-character Apple Developer Team ID.' >&2; exit 2
  fi
fi
if [[ "$mode" == test ]] && pgrep -x 'Mac Companion' >/dev/null; then
  echo 'Quit Mac Companion before running its signed test host.' >&2; exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$root/scripts/prepare.py" --team "${COMPANION_TEAM:-UNSIGNED00}"
args=(-project "$root/.build/Source/Mos.xcodeproj" -scheme Debug -configuration Debug
      -destination 'platform=macOS' -derivedDataPath "$root/.build/DerivedData"
      -clonedSourcePackagesDirPath "$root/.build/SourcePackages")
if [[ "$mode" == check ]]; then
  xcodebuild "${args[@]}" build-for-testing CODE_SIGNING_ALLOWED=NO
else
  xcodebuild "${args[@]}" "$mode" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM="$COMPANION_TEAM"
fi
