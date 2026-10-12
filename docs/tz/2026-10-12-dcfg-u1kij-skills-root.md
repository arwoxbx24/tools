# TZ dcfg-u1kij — safe-delete `dir`: allow default root `/root/.claude/skills`

## U1
Goal: `bin/safe-delete dir /root/.claude/skills/<name>` passes the root check, so agents can retire a renamed personal skill with the usual 14-day copy. Today it refuses: `safe-delete: вне разрешённых корней: /root/.claude/skills/methods` (rc 2).

Change (one line): `bin/safe-delete:59` default `roots=` list — append `:/root/.claude/skills`. Nothing else in the root logic changes. Line 58 bans (`/etc/claude-code/*`, `$HOME/.ssh/*`, `$HOME/.claude/settings*.json`) stay exactly as they are. The `SAFE_DELETE_ROOTS` override rule (roots under `/tmp` only) stays.

Test (`bin/safe-delete-test`, add next to T15, same style): tests run with `SAFE_DELETE_ROOTS` under `/tmp`, so the new default cannot be exercised by a real deletion. Add:
- T-new-1: `grep -c ':/root/.claude/skills}' bin/safe-delete` (the default roots line) → 1.
- T-new-2: with `SAFE_DELETE_ROOTS` unset, `safe-delete --bk <tmp> file /root/.claude/settings.json` → refused, stderr contains `запрещённый путь`, file still exists.
- T-new-3: with `SAFE_DELETE_ROOTS` unset, `safe-delete --bk <tmp> file /etc/claude-code/CLAUDE.md` → refused, file still exists.
Never delete a real file under `/root/.claude` in tests.

Discovery: index repowise/CBM checked, not needed — one named line `bin/safe-delete:59`, tests `bin/safe-delete-test:127`. Do not read other files.
Principles: KISS, YAGNI, fail fast; no refactor of neighbouring code.

## Sources
- Failure observed 12.10: command `safe-delete dir /root/.claude/skills/methods` → `вне разрешённых корней`, rc 2.
- Law: `/root/CLAUDE.md` "НЕ ТОРМОЗИТЬ" — fix a false wrapper refusal with a test that real bans still refuse.

## Acceptance
1) `bash bin/safe-delete-test` → all pass, includes T-new-1..3.
2) `git diff --stat` → only `bin/safe-delete` (1 line) and `bin/safe-delete-test`.
