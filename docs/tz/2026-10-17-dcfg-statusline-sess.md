# TZ dcfg-z931m — statusline: ship always visible + session block

Atom: dcfg-z931m. Project: worktree of /root/workspaces/tools. Discovery: repowise (index checked); facts are file:line.
Principles: KISS, YAGNI, minimal diff. No new files, no new dependencies.

## U1

FILE: hooks/statusline-segment.sh
FILE: hooks/statusline-segment-test.sh

Facts:
- hooks/statusline-segment.sh:3,7,15 — field list `folder|lines|ctx|ship|sdk|five|week`.
- hooks/statusline-segment.sh:33,35 — `.session_id` is read into `$sid`.
- seg_ship: the final `else return` (no busy, no stuck, no delivered) prints nothing, so the block disappears.

Change (hooks/statusline-segment.sh):
1. New field `sess`: add it to the usage lines (3, 7) and the case list (15). `seg_sess`: if `$sid` is empty → print nothing; else print `claude ` + the last 6 characters of `$sid` (e.g. sid `f4ea9812-...-183f5b37174d` → `claude 37174d`).
2. seg_ship: when there is nothing busy, stuck or delivered, print `ship ✓ 0` instead of returning empty. Keep the early return when `$sid` is empty or the submissions dir is missing, but in the missing-dir case with a non-empty sid also print `ship ✓ 0`.
3. Nothing else changes.

Test (hooks/statusline-segment-test.sh): add `sess` to the field loop if it checks all fields; add cases:
- sess with the fixture session_id → `claude <last 6>`; sess without session_id → empty.
- ship with an empty submissions dir and a session id → `ship ✓ 0`.
- Run `bash hooks/statusline-segment-test.sh` → report the PASS line.

Forbidden: editing any other file; rm outside test temp; reading ~/.ssh, secrets, .env; network; git push.

## Source passport
- code.claude.com/docs/en/statusline — stdin JSON field `session_id` (already used at statusline-segment.sh:33).
