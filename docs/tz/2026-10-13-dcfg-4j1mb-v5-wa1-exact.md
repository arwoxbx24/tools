# TZ dcfg-4j1mb v5 — W-A1 exact edits (per-repo Beads root)

v5 reason: v4 run ended rc 0 with zero edits (t=1670, read-only). This TZ lists exact edits. Do them, nothing else. No exploration beyond the named lines.
Files: `bin/git-auto-lib`, `bin/ship-post`, `bin/ship-post-test` only. Do not touch `bin/git-ci-enable*` (already staged).

1. `bin/git-auto-lib`, after `ga_repo_of` (ends ~line 62), add:
```
ga_beads_root(){ # <path> — dir holding .beads for the repo of <path>; none -> SHIP_POST_BEADS_ROOT
	local gd d
	gd=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && d=$(dirname "$gd") || d=$1
	while [[ -n $d && $d != / ]]; do [[ -d $d/.beads ]] && { echo "$d"; return 0; }; d=$(dirname "$d"); done
	echo "${SHIP_POST_BEADS_ROOT:-/root/workspaces/projects}"
}
```
2. `bin/ship-post:77` replace `bd_cmd` with two helpers:
```
bd_cmd(){ (cd "${atom_root:-$SHIP_POST_BEADS_ROOT}" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
bd_home(){ (cd "$SHIP_POST_BEADS_ROOT" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
```
3. Incident and ledger calls use `bd_home`: lines ~369 (`show "$id"`), ~373 (`create "[ship-post] INFRA exit`), ~380 (`update "$id"`), ~422 (`update "$inc"`), ~584 (`info --json`). All other `bd_cmd` calls stay.
4. Set `atom_root`: in `do_submit` right after the worktree is resolved to `wt_real` (before line ~140 `bd_cmd show`): `atom_root=$(ga_beads_root "$wt_real")`. In `scan_repo` right after `repo=$(realpath "$repo")` (~line 518): `atom_root=$(ga_beads_root "$repo")`.
5. In `deliver_one`, where `"$ship_bin"` is invoked, prefix the call with `BEADS_DIR="${atom_root:-$SHIP_POST_BEADS_ROOT}/.beads"`.
6. `scan_repo` line ~534: replace `st=$(bd_cmd show "$atom" --json) || { failed=$((failed+1)); continue; }` with: on failure, if `bd_cmd show` stderr contains `not found`, write `{"stage":"unknown-atom"}` (jq -n, plus atom and sha) to `$(receipt_file "$repo" "$atom" "$head")` once, print `skip $atom unknown-atom`, `skip=$((skip+1)); continue`; other failures keep `failed+1`. Line ~545 case: add `unknown-atom` to the `wait-owner|prod-hold) continue` list. (`head` is already set at ~532.)
7. Line ~546–547: a receipt with stage `wait-owner` whose sibling log `"$rf.log"` contains `prod:wait-owner no-ci` is removed once (same as the legacy `'wait-owner no-ci'` branch) so ship re-runs it.
8. `bin/ship-post-test`: append one block `test_beads_root` (call it from the runner like other blocks): temp repo with its own `.beads` dir; assert `ga_beads_root <worktree of that repo>` prints the repo dir, and a dir without `.beads` above prints `SHIP_POST_BEADS_ROOT`.
Then run `bin/ship-post-test` once. Output: failures in full, `checks=` line, `git diff --stat`.
Forbidden: network, real remotes, `rm -rf` outside temp dirs, other files.
