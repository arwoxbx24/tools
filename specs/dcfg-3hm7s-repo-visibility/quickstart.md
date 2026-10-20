# Quickstart: repo-visibility

Run from the tools checkout (or the worktree).

1. `bash bin/repo-visibility-test` → last line `PASS 6/6`.
2. `bin/repo-visibility --help` → `usage: …`, rc 0.
3. `bin/repo-visibility publish arwox-biz` → `refused: arwox-biz not in public allowlist`, rc 1; `gh repo view arwoxbx24/arwox-biz --json visibility -q .visibility` → `PRIVATE`.
4. `bin/repo-visibility publish eurosteklo` → `refused: eurosteklo is never_public`, rc 1; view → `PRIVATE`.
5. `bin/repo-visibility publish arwox-v3-src` → `secrets: 0`, `arwox-v3-src: PUBLIC`; view → `PUBLIC`.
6. `bin/repo-visibility report` → `agent-contour PRIVATE 501`, `private total: 511/2000`, `all repos total: …/2000`.
