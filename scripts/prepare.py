#!/usr/bin/env python3
"""Prepare a separate local build tree; never alter the published source."""
import argparse
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def prepare(team: str) -> Path:
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Expected a 10-character signing team')
    destination = ROOT / '.build' / 'Source'
    destination.mkdir(parents=True, exist_ok=True)
    # Replace only our generated tree. Never copy a private build, Git history or credentials.
    for name in ['Mos', 'MosTests', 'Mos.xcodeproj', 'AWDLHelper']:
        src, dst = ROOT / name, destination / name
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst, ignore=shutil.ignore_patterns('xcuserdata', '*.xcuserstate', '.DS_Store'))
    replacements = 0
    for path in destination.rglob('*'):
        if not path.is_file():
            continue
        try:
            source = path.read_text()
        except UnicodeDecodeError:
            continue
        if 'YOUR_TEAM_ID' in source:
            replacements += source.count('YOUR_TEAM_ID')
            path.write_text(source.replace('YOUR_TEAM_ID', team))
    if replacements < 3:
        raise RuntimeError('Signing template was incomplete; do not build a mismatched helper')
    return destination

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--team', required=True)
    print(prepare(parser.parse_args().team))
