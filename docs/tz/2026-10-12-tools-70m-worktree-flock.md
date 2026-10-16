# Code Channel worktree lock

## U1 — Native nonblocking lock

Owner goal: a Code Channel invocation must reject another invocation for the same worktree immediately, while different worktrees can run independently.

Architecture: replace the process-name `pgrep` tree scan in `bin/code-channel` with `flock -n` on a stable lock file in the existing Code Channel state directory, keyed by the canonical project path. Hold its descriptor for the invocation. Use installed shell/coreutils only. No model, timeout, provider, or retry changes.

Scope: `bin/code-channel` and this TZ only. The owner assigned timeout and model edits to another agent; do not modify those lines. Do not invoke ship-post or create Beads issues from the nested executor. Do not run a model solely to test the lock.

Acceptance: `rg -c 'pgrep -f --' bin/code-channel` has zero matches; `rg -c 'flock -n' bin/code-channel` prints `1`; `bash -n bin/code-channel` and `git diff --check` exit zero; the diff changes only the collision guard. This actual code task is the one permitted model run. The coordinator will inspect and submit the result.

Rollback: revert this own branch's guard change before delivery if acceptance fails. No other file or contour may be changed.
