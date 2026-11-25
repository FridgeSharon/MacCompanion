# Project recovery

From the root of a fresh clone, an authorized maintainer can retrieve the private recovery guide using Git and the signed-in 1Password CLI. Run this block in Bash. It creates a new owner-only staging directory inside the checkout’s Git metadata.

```bash
(
  set -euo pipefail
  umask 077
  stage=$(mktemp -d "$(git rev-parse --absolute-git-dir)/project-recovery.XXXXXXXX")
  op document get 'MacCompanion — recovery instructions (2026-11-25)' > "$stage/guide.md"
  test -s "$stage/guide.md"
  printf 'Recovery guide and staged material: %s\n' "$stage"
)
```

Open the downloaded guide for project-specific setup and provider recovery steps. If 1Password asks you to choose between matching titles, select your project’s designated maintainer vault using `--vault`.
