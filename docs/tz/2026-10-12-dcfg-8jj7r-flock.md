# TZ dcfg-8jj7r — code-channel: per-worktree advisory lock (flock)

## U1

Source: plan `docs/plans/2026-10-10-1806-feat-code-channel-go-streams-plan.md:95` (projects repo): "Acquire an advisory lock keyed by the canonical worktree path before a code run and release it when that run ends; separate worktrees may run concurrently, while two runs against one worktree serialize or fail promptly." Decision: fail promptly (no waiting, owner 12.10: no waits, no timers).

Files: `bin/code-channel`, `bin/code-channel-test` only.

1. `bin/code-channel`: right after the existing line `cd -- "$project" || exit 3`, take a non-blocking lock on a file in the state dir `$S` whose name is derived from the canonical project path (`$PWD` after the cd; e.g. its sha1sum, first 16 hex chars), using `flock -n` on a dedicated file descriptor (e.g. `exec 9>"$S/worktree.<hash>.lock"`). If the lock is held: `fail "worktree занят другим запуском: $PWD"` and `exit 25` (25 is unused; 21, 22, 24 are taken). The lock is released automatically when the process exits; do not add unlock code. No timers, no `-w`, no sleep, no new numeric constants other than the fd and exit code.
2. `bin/code-channel-test`: add one check, using the existing `check` helper and stubs, that while the lock file for `$project` is held by the test (`flock -n` on the same derived path under the test state dir), a run against `$project` exits 25; and update the final summary line to the new total. Do not change other checks.
3. `docs/code-channel.md` is out of scope.

Rules: no other files, no model test runs, do not commit. Index: repowise/CBM checked; разведка — repowise.

Done check:
1. `grep -c flock bin/code-channel` → ≥ 1
2. `grep -cE "timeout [0-9]" bin/code-channel` → `0`
3. `bash -n bin/code-channel` → rc 0
4. `bash bin/code-channel-test` → all PASS, rc 0
