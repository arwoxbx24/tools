# TZ dcfg-n2noe.4 — safe-delete: allow Claude session transcripts root

## U1
Owner word 17.10 ("yes"): empty Claude Code session transcripts in `/root/.claude/projects/<slug>/*.jsonl` must be removable via safe-delete. Today `safe-delete file <transcript>` → rc 2 "вне разрешённых корней".

FILE: bin/safe-delete
FILE: bin/safe-delete-test

Files (only these two):
- `bin/safe-delete` line 65: in the default `roots=${SAFE_DELETE_ROOTS:-...}` list, replace `/root/.claude/projects/-root-workspaces-projects/memory` with `/root/.claude/projects` (the memory dir is inside it). Nothing else changes. Whole `/root/.claude` must NOT become a root.
- `bin/safe-delete-test`:
  - T18 (line ~149-151): it checks the memory root string; change its first condition to check `:/root/.claude/projects:` instead, keep the second condition (no whole `/root/.claude` root) unchanged; rename comment to "default roots include claude projects root, not whole .claude".
  - Add T83 before the final count line, in the T80 style: with `env -u SAFE_DELETE_ROOTS`, create `/root/.claude/projects/sd-test-$$/x.jsonl`, run `safe-delete --bk "$bk" file` on it → rc 0, file gone; then remove the empty `/root/.claude/projects/sd-test-$$` dir with `safe-delete --bk "$bk" dir`; print `PASS T83 claude_projects_root`.
  - Final line: `[[ $ok == 83 ]]` → `[[ $ok == 84 ]]`.
- T55 (`/root/.claude/settings.json` refused) and T56 must still PASS unchanged.

Principles: KISS, YAGNI, minimal diff, no refactor of neighbouring code.
разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Bans: no rm -rf outside /tmp and test dirs, no ~/.ssh, no secrets, no /etc writes, no git push.
Verification: the lead agent runs `bin/safe-delete-test` after the edits (it is a listed file, so no Check line).
