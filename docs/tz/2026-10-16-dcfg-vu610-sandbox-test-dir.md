# TZ — safe-delete dir removes agent test repos in the sandbox (atom dcfg-vu610)

Source: procedure `projects/docs/LAWS-PROCEDURES.md:55-58` — agent test dirs `/root/workspaces/sandbox/<test-…>` are deleted by the agent. Law «НЕ ТОРМОЗИТЬ» (`/root/CLAUDE.md`): a false refusal of an own wrapper is a tool defect; fix it with a test that real bans still refuse.
Exploration: codebase-memory / grep -n (done by lead); index: repowise/CBM checked.

Cause: `safe-delete dir /root/workspaces/sandbox/test-31e8-sdk` → rc 2 `запрещённый сегмент: …/.git/HEAD`. `bin/safe-delete:19` (`self_contained`) returns 1 when `<dir>/.git` exists, so `allow_git_under` stays empty at `:145`, and `check_path` `:66-68` refuses the `.git` segment.

## U1
FILE: bin/safe-delete
FILE: bin/safe-delete-test

1. `bin/safe-delete`, next to `allow_git_under=` (line 9): add `sandbox=${SAFE_DELETE_SANDBOX:-/root/workspaces/sandbox}` and `force_copy=`. After the `refuse` function exists (where `SAFE_DELETE_ROOTS` is validated is the model, line 62), refuse when `SAFE_DELETE_SANDBOX` is set and does not start with `/tmp/`: message `корень не под /tmp: <value>`, same exit code as other refusals. Place this check so it runs before any deletion in every mode.
2. `bin/safe-delete`, `dir)` mode, line 145: before the `self_contained` test, if `$dir` is a direct child of `$sandbox` whose name starts with `test-` (`[[ $dir == "$sandbox"/test-* && ${dir#"$sandbox"/} != */* ]]`), set `allow_git_under=$dir` and `force_copy=1`; otherwise keep the current line unchanged.
3. `bin/safe-delete`, `delete_file`, line 84: `if git_file "$1"; then` → `if [[ -z $force_copy ]] && git_file "$1"; then` (a git pin inside the repo being deleted could not be restored; files get copies instead).
4. Nothing else changes: the ban list `secrets hh-scoring .codex .git .beads`, clients, `.repowise`, `.env*`, `*.pem`, `*.key`, roots, other modes.
5. `bin/safe-delete-test`: add T67-T70 before the final count, in the style of T29-T37 (`"$bin/safe-delete" --bk "$bk" …`, `ok=$((ok+1))`), with `SAFE_DELETE_SANDBOX="$d/sb"` (under `$d`, which is already `SAFE_DELETE_ROOTS`):
   - T67: `git init -q "$d/sb/test-x"`, commit one file `a.txt` (set user.email/user.name locally) → `dir "$d/sb/test-x"` rc 0, the dir is gone, output has ≥1 line `удалено:` and 0 lines with `основание: git`.
   - T68: same kind of repo at `"$d/sb/keep-x"` (name without `test-`) → rc 2, output contains `запрещённый сегмент`, dir still exists.
   - T69: `"$d/sb/test-y"` with a file `.beads/f` (no git needed) → rc 2, dir and `.beads/f` still exist.
   - T70: `SAFE_DELETE_SANDBOX=/root/workspaces/sandbox` with target `"$d/sb/test-z"` (a dir with one file) → rc 2, output contains `корень не под /tmp`, `"$d/sb/test-z"` still exists.
   - Final lines: `[[ $ok == 70 ]] || exit 1` and `echo "итог: PASS 70, FAIL 0"`.

## Check
- `bash -n bin/safe-delete` → rc 0
- `bash bin/safe-delete-test 2>&1 | tail -n 1` → `итог: PASS 70, FAIL 0`
- Red-first: T67 fails on the code before items 1-3.

## Bans
No commit, no push. Do not touch `.env`/secrets/`~/.ssh`/`/etc`; no `rm -rf` outside /tmp; no new dependencies or abstractions (KISS, YAGNI); one new env variable.
