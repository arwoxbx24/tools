# TZ dcfg-rgo12 — code-channel: refuse executor changes outside the TZ files; scratch only in /tmp

Source defect: projects `docs/tz/2026-10-11-ship-post-submit-defects.md` D9. Executor left `worktree-tmp/` (48 files) and edits not asked by the TZ; code-channel reported success. Root cause: no machine check of changed paths after the run.

## U1

Files: `bin/code-channel`, `bin/code-channel-test` only. разведка — repowise.

This task has 2 independent file sets: set A = `bin/code-channel`, set B = `bin/code-channel-test`. The contract between them is fixed below, so both can be written at the same time.

Contract:
- A TZ may declare its files on a line that starts with `Files:`; the allowed paths are the backticked paths on that line (the first such line only). No `Files:` line → no check, behavior unchanged.
- Code mode only, only after the executor run ended with rc 0: take the worktree changes made during the run (compare `git status --porcelain --untracked-files=all` taken before the run with the one after the run). Ignore the TZ file itself. Any new path not in the allowed list → print to stderr `out-of-scope: <paths separated by spaces>` and exit 26 (26 is unused in `bin/code-channel`). All paths allowed → behavior unchanged.
- The executor brief block (the `prompt=$(printf '...\n\n%s' "$prompt")` lines near 151-155) gets one more line of the same form: `Scratch and temporary files go to /tmp only, never inside the worktree`.

Set A, `bin/code-channel`: implement the contract above. Do not touch the existing resume loop, flock, `timeout 1800` lines or the ladder.

Set B, `bin/code-channel-test`: follow the existing stub style of the file.
1. New check: TZ with `Files: \`bin/x\` only.`, stub executor creates `worktree-tmp/a` → rc 26 and stderr contains `out-of-scope: worktree-tmp/a`.
2. New check: same TZ, stub executor changes only `bin/x` → rc 0.
3. Extend check 16 with `&& grep -Fq -- "Scratch and temporary files go to /tmp only, never inside the worktree" "$log"`.

Rules: SOLID, DRY, KISS, YAGNI; no other files; no model test runs; do not commit; do not create branches.

Done check:
1. `grep -c "out-of-scope" bin/code-channel` → ≥ 1
2. `bash bin/code-channel-test | tail -n 1` → `PASS N/N`, rc 0
