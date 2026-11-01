#!/usr/bin/env python3
"""Publication gate for this source snapshot; reports paths, never secret values."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP = {'.git', '.build', '__pycache__'}
EXCLUDED = ['Mos/Logi', 'Mos/Integration', 'Mos/ButtonCore/LogiStandardMouseButtonAlias.swift']
REQUIRED = ['LICENSE', 'README.md', 'LICENSING.md', 'CREDITS.md', 'THIRD_PARTY_NOTICES.md',
            'LICENSES/CC-BY-NC-4.0.txt', 'LICENSES/Mos-original-LICENSE.txt',
            'LICENSES/MacMouseFix.txt', 'LICENSES/Rectangle-MIT.txt',
            'LICENSES/AWDLControl-MIT.txt', 'LICENSES/Charts-Apache-2.0.txt',
            'LICENSES/LoginServiceKit-Apache-2.0.txt']
PATTERNS = [r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
            r'github_pat_[A-Za-z0-9_]{20,}', r'gh[pousr]_[A-Za-z0-9]{25,}',
            r'AKIA[A-Z0-9]{16}', r'/Users/[^/\s]+/',
            r'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;',
            r'IOHIDManagerCreate\s*\(']

def audit():
    errors, count, total = [], 0, 0
    for name in REQUIRED:
        if not (ROOT/name).is_file(): errors.append('Missing notice: '+name)
    for name in EXCLUDED:
        if (ROOT/name).exists(): errors.append('Excluded backend restored: '+name)
    for path in ROOT.rglob('*'):
        relative = path.relative_to(ROOT)
        if any(part in SKIP for part in relative.parts) or not path.is_file(): continue
        count += 1
        total += path.stat().st_size
        if any(part in {'.local-state', 'xcuserdata'} for part in relative.parts):
            errors.append('Private metadata: '+str(relative))
        if path.suffix.lower() in {'.p12','.p8','.pem','.key','.mobileprovision','.provisionprofile','.xcuserstate'}:
            errors.append('Private signing/state file: '+str(relative))
        if any(part.endswith(('.app','.dSYM')) for part in relative.parts):
            errors.append('Compiled artifact: '+str(relative))
        # Audit policy literals are patterns, not credentials. All other text is scanned.
        if relative.as_posix() == 'scripts/audit_export.py': continue
        try: text = path.read_text()
        except UnicodeDecodeError: continue
        for pattern in PATTERNS:
            if re.search(pattern,text): errors.append('Review matched content: '+str(relative))
    # The original MIT/custom notices must stay identical in source and license directory.
    for left,right in [('MacMouseFix.txt','MacMouseFix-LICENSE.txt'),
                       ('Rectangle-MIT.txt','Rectangle-LICENSE.txt'),
                       ('AWDLControl-MIT.txt','AWDLControl-LICENSE.txt')]:
        a,b=ROOT/'LICENSES'/left,ROOT/'Mos/Companion'/right
        if a.exists() and b.exists() and a.read_text().strip()!=b.read_text().strip():
            errors.append('Notice mismatch: '+right)
    print(f'Checked {count} source/resource files ({total} bytes).')
    for error in errors: print(error, file=sys.stderr)
    if errors: return 1
    print('Source/export license and privacy gates passed.')
    return 0

if __name__=='__main__': sys.exit(audit())
