# TZ dcfg-32uaa — safe-delete worktree: remove a git-ignored .repowise cache of a linked worktree

## U1
Goal: `safe-delete worktree <linked-worktree>` succeeds when the worktree holds a git-ignored `.repowise/` cache at its top level (index files written by repowise after commit). Today it refuses: `запрещённый сегмент: <wt>/.repowise/centrality_cache.pkl` (bin/safe-delete:70 via check_file, called at :161 and inside delete_file at :164).

Discovery: repowise / code index first (line "разведка — repowise"); index: repowise/CBM checked, missing → `tools/bin/code-memory-enable`.

Files you own: `bin/safe-delete`, `bin/safe-delete-test`. Nothing else.

Change (worktree mode only, lines 155-168):
- A file is a "worktree repowise cache" when ALL hold: its path is `$wt/.repowise/<...>` (top-level `.repowise` dir of this worktree, not `.repowise-*`, not nested deeper dirs named .repowise), and `git -C "$wt" check-ignore -q -- <rel>` is true.
- Such files skip the forbidden-segment check only; they are still backed up as a restorable copy exactly like other non-git files in delete_file (same backup dir, same ledger line, same `восстановить: safe-delete restore N` output). Implement by a minimal flag/variable around the existing check, not a copy of delete_file.
- Every other path keeps the current rule: line 70 unchanged for file, dir, tmp modes and for the main checkout; non-ignored `.repowise` files inside a worktree still refuse; all other forbidden segments unchanged.

Tests (append to bin/safe-delete-test in its style, all fixtures under its existing temp dir `$d`, update the final count):
- T61: linked worktree with `.gitignore` containing `.repowise/` and file `.repowise/cache.pkl` → rc 0, worktree dir gone, a backup copy of cache.pkl exists under `$bk`.
- T62: linked worktree with NOT ignored `.repowise/x` → rc 2, err contains `запрещённый сегмент`, worktree still exists.
- T63: `safe-delete file "$d/w/.repowise/f"` (main checkout, ignored or not) → rc 2, file still exists.
Run `bash bin/safe-delete-test` once; expected last line `итог: PASS 63, FAIL 0`.

Principles: KISS, YAGNI, minimal diff, fail fast, no new options or env vars. Do not touch hooks, settings, repowise config. No `rm -rf`, no paths outside the test temp dir.

Rollback: revert the commit.
