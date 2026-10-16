# TZ dcfg-8mg87 — safe-delete link: own live alias inside tools (owner law 10.10 "НЕ ТОРМОЗИТЬ")

Why: `safe-delete link /root/workspaces/tools/claude-agent-sdk` -> rc 2 "симлинк живой" (bin/safe-delete:184). The link is an agent's own temp alias to `/root/workspaces/tools/sdk-agent`; removing a symlink loses no data. Existing guard T23 (live link in other roots refused) must stay.
Index: repowise/CBM checked, not needed (one bash file). Principles: KISS, YAGNI, minimal diff; keep every existing check, message and exit code.

## U1 — bin/safe-delete, bin/safe-delete-test
1. In the `link)` branch, replace the unconditional live-link refusal (`[[ ! -e $1 ]] || refuse "симлинк живой: $1"`) by: if the link is live, allow it only when BOTH the link path (realpath of its directory + basename) AND the link target (`realpath -e -- "$1"`) are under the live-link root `lroot=${SAFE_DELETE_LIVE_LINK_ROOT:-/root/workspaces/tools}`; otherwise refuse with the same text "симлинк живой: $1". If `SAFE_DELETE_LIVE_LINK_ROOT` is set it must be under /tmp (else refuse "корень не под /tmp: ..."), same as SAFE_DELETE_ROOTS.
2. A live link allowed by item 1 skips the `roots` check (it is under the live-link root instead); dangling links keep the current roots logic unchanged. Logging (`log link ... backup-ok`, `rm`, `log ... deleted`) unchanged; the target stays recorded in the ledger.
3. Test T23b in `bin/safe-delete-test` (after T23): with `SAFE_DELETE_LIVE_LINK_ROOT=$d/lr` (create dir), a live link `$d/lr/alias` -> `$d/lr/target` (a file) is deleted (rc 0, link gone, target file still present); a live link `$d/lr/out` -> `$d/live-target` (outside lr) is refused rc 2 and stays. T23 unchanged and passing. Update the final total count.

Files: `bin/safe-delete` `bin/safe-delete-test` `docs/tz/2026-10-16-safe-delete-live-tools-link.md`
Check: bin/safe-delete-test
