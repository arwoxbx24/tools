# TZ dcfg-p6i3p — safe-delete branch: local ref removable when its SHA is already archived on origin as an archive tag

## U1
Discovery: repowise first (line "разведка — repowise"); index: repowise/CBM checked, missing → `tools/bin/code-memory-enable`.
Files you own: `bin/safe-delete`, `bin/safe-delete-test`. Nothing else.
Method: TDD. Add test cases FIRST (append to bin/safe-delete-test in its style, fixtures under its temp dir `$d`, update the final count), run `bash bin/safe-delete-test`, confirm the new positive case FAILS, then implement.

Facts:
- branch mode (bin/safe-delete ~245-300): when the branch is NOT on origin, the local ref is removed only if it is an ancestor of origin/main or the head of a merged PR; otherwise `refuse "нет на origin: $br"`.
- The first pass of the same mode pushes the remote branch SHA to tag `archive/<branch with / → ->-<YYYYMMDD>` (optionally `-<HHMMSS>` suffix) and removes the remote branch. So a closed-unmerged PR branch is fully saved, yet the second pass refuses the local ref.
- Fact 15.10: local claude/dcfg-n575n-control-md = 8454083bb493…, origin tag archive/claude-dcfg-n575n-control-md-20261015 = same SHA.

Change (inside the "not on origin" branch only):
- Accept the local ref when `git -C "$repo" ls-remote origin "refs/tags/archive/${br//\//-}-*"` lists a line whose SHA equals the local SHA (exact match). Then update-ref -d and the existing ledger line exactly like the other accepted paths.
- Everything else unchanged: main/master/codex/* refusals, open-PR refusal, unarchived unmerged local branches still refused with the same message.

Tests (SAFE_DELETE_GH=false fixtures with a bare origin repo under `$d`):
- local branch whose SHA equals origin tag `archive/<slug>-20261015` → rc 0, ref gone, ledger line written.
- local branch with an archive tag pointing to a DIFFERENT SHA → rc 2, `нет на origin`, ref kept.
- local branch with no archive tag → rc 2, ref kept.
Note: if the "not on origin" path today requires GH=true for the merged-PR check, keep that requirement for the merged-PR branch only; the archive-tag check must work with SAFE_DELETE_GH=false (git only).
Run `bash bin/safe-delete-test` once; last line `итог: PASS N, FAIL 0`.

Principles: KISS, YAGNI, minimal diff, fail fast; no new options or env vars; no paths outside the test temp dir; no `rm -rf` outside it.
Rollback: revert the commit.
