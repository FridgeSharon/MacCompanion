#!/usr/bin/env python3
"""Verify a Developer ID app before notarization, and again before packaging."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'com.github.FridgeSharon.MacCompanion'
LICENSES = {
    'MacMouseFix.txt': 'MacMouseFix-LICENSE.txt',
    'CC-BY-NC-4.0.txt': 'Mos-CC-BY-NC-4.0-LICENSE.txt',
    'Rectangle-MIT.txt': 'Rectangle-LICENSE.txt',
    'AWDLControl-MIT.txt': 'AWDLControl-LICENSE.txt',
    'Charts-Apache-2.0.txt': 'Charts-LICENSE.txt',
    'LoginServiceKit-Apache-2.0.txt': 'LoginServiceKit-LICENSE.txt',
}


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}')
    return result


def verify(app, team, before_notarization=False):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Expected a 10-character signing team')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != APP_ID:
        raise ValueError('This is not the public Mac Companion app')
    if not re.fullmatch(r'\d{8}\.\d+', info.get('CFBundleVersion', '')):
        raise ValueError('Expected a unique YYYYMMDD.N release build number')
    resources = app / 'Contents/Resources'
    for source, bundled in LICENSES.items():
        if (ROOT / 'LICENSES' / source).read_bytes() != (resources / bundled).read_bytes():
            raise ValueError('License is missing or modified: ' + bundled)
    notices = (resources / 'ThirdPartyNotices.txt').read_text()
    for credit in ['Mac Mouse Fix', 'Noah Nuebling', '2dae68a01ebcb4c645161160a7872a60ecf58ace',
                   'Mos', 'Caldis', 'Rectangle', 'Spectacle', 'AWDLControl', 'Charts', 'LoginServiceKit']:
        if credit not in notices:
            raise ValueError('Missing bundled credit: ' + credit)

    helper = app / 'Contents/Library/Helpers/MacCompanionAWDLHelper'
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(app))
    for code, identifier in [(app, APP_ID), (helper, APP_ID + '.AWDLHelper')]:
        signature = run('/usr/bin/codesign', '-d', '--verbose=4', str(code)).stderr
        if 'Authority=Developer ID Application:' not in signature:
            raise ValueError('Expected Developer ID Application signing: ' + code.name)
        if f'TeamIdentifier={team}\n' not in signature or f'Identifier={identifier}\n' not in signature:
            raise ValueError('Signing team/identifier mismatch: ' + code.name)
        flags = re.search(r'flags=0x([0-9a-fA-F]+)', signature)
        if not flags or not (int(flags.group(1), 16) & 0x10000):
            raise ValueError('Hardened runtime is disabled: ' + code.name)
        if 'Timestamp=' not in signature:
            raise ValueError('Missing secure signing timestamp: ' + code.name)
        entitlements = run('/usr/bin/codesign', '-d', '--entitlements', '-', '--xml', str(code)).stdout
        if entitlements.strip():
            values = plistlib.loads(entitlements.encode())
            if values.get('com.apple.security.get-task-allow'):
                raise ValueError('Debugging entitlement enabled: ' + code.name)
    for code in [executable, helper]:
        if set(run('/usr/bin/lipo', '-archs', str(code)).stdout.split()) != {'arm64', 'x86_64'}:
            raise ValueError('Expected both Apple Silicon and Intel architectures: ' + code.name)
    for code, peer in [(executable, APP_ID + '.AWDLHelper'), (helper, APP_ID)]:
        strings = run('/usr/bin/strings', '-a', str(code)).stdout
        requirement = (f'anchor apple generic and identifier "{peer}" '
                       f'and certificate leaf[subject.OU] = "{team}"')
        if requirement not in strings or 'YOUR_TEAM_ID' in strings:
            raise ValueError('Incorrect embedded XPC peer requirement: ' + code.name)
    if not before_notarization:
        run('/usr/bin/xcrun', 'stapler', 'validate', str(app))
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=4', str(app))
    print(f"Verified {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}): "
          'licenses, credits, universal app/helper, Developer ID, runtime and entitlements.')
    print('Notarization pending.' if before_notarization else 'Stapled ticket and Gatekeeper acceptance verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--team', required=True)
    parser.add_argument('--before-notarization', action='store_true',
                        help='Skip ticket/Gatekeeper checks only for the notarization submission')
    args = parser.parse_args()
    try:
        verify(args.app.resolve(), args.team, args.before_notarization)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Release verification failed: {error}\n')
