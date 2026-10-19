# TZ dcfg-6vk80: safe-delete — allow settings.json.bak* backups in $HOME/.claude

Skills: prod
Разведка — repowise (индекс: repowise/CBM проверен, проект `root-workspaces-tools`).

## Problem
`bin/safe-delete file /root/.claude/settings.json.bak` refuses with `вне разрешённых корней` (roots at `bin/safe-delete:89` do not include `$HOME/.claude`, only its `projects` and `skills` subdirs). The owner's goal (19.10) is to remove stale backup copies of user settings through safe-delete with a restore number. The wrapper already keeps a 14-day copy of every non-git-clean file, so the content stays restorable.

## Change (only these two files)
1. `bin/safe-delete`, function `check_resolved` (around line 93-94): before the `[[ $okr ]] || refuse "вне разрешённых корней: $p"` line, also accept exactly a regular file whose path matches `"$HOME"/.claude/settings.json.bak*` (direct child of `$HOME/.claude`, no subdirectories, not a directory). One line, for example:
   `[[ $p == "$HOME"/.claude/settings.json.bak* && $p != "$HOME"/.claude/*/* && -f $p && ! -L $p ]] && okr=1`
   Comment one line why: backups of user settings, 14-day copy keeps them restorable.
   Do NOT add `$HOME/.claude` to the roots list; do NOT touch the forbidden-path line 87 (`/etc/claude-code/*`, `~/.ssh/*`, `$HOME/.claude/settings*.json` must still refuse).
2. `bin/safe-delete-test`: add tests after T56, numbered with the next free numbers (check the file for the highest Tnn and keep the final summary count consistent with how the file counts `ok`):
   - Ta: create `/root/.claude/settings.json.bak-sdtest-$$` (echo test content), run `"$bin/safe-delete" --bk "$bk" file <it>`; PASS when rc 0, output contains `восстановить: safe-delete restore`, and the file no longer exists.
   - Tb: `/root/.claude/settings.json` still refuses with `запрещённый путь` and survives (T55 already covers; do not duplicate).
   - Tc: a directory `/root/.claude/settings.json.bak-sdtest-dir-$$` (mkdir) refuses with `dir` mode and with `file` mode, rc 2, and still exists; remove it at the end of the test with `rmdir`.
   - Td: `/root/.claude/other-sdtest-$$.bak` (not settings.json.bak*) refuses with `вне разрешённых корней`, rc 2, file survives; remove it at the end with `rm -f` (test-local cleanup, as other tests in this file do).

## Acceptance
1) `bash bin/safe-delete-test` — all PASS, zero FAIL (paste the summary line).
2) `git diff --stat` touches only `bin/safe-delete`, `bin/safe-delete-test`.

## Forbidden
No other files. No `rm -rf` outside /tmp and the test's own temp dirs. Do not read or write `~/.ssh`, `/etc`, secrets, `.env`, `auth.json`. Do not edit `/root/.claude/settings.json`. Principles: KISS, YAGNI, minimal diff.
