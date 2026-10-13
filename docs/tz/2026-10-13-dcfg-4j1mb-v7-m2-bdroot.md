# TZ dcfg-4j1mb v7 M2 — paste only, no exploration
v7 reason: v5 single run too slow; split into 3 parallel micro edits.
File: `bin/ship-post` only. No test run (another worker adds tests).

1. Replace the one-line function `bd_cmd(){ ... }` (~line 77) with:
```
bd_cmd(){ (cd "${atom_root:-$SHIP_POST_BEADS_ROOT}" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
bd_home(){ (cd "$SHIP_POST_BEADS_ROOT" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
```
2. Change `bd_cmd` to `bd_home` ONLY in these calls (find with `grep -n`): `bd_cmd show "$id"`, `bd_cmd create "[ship-post] INFRA exit`, `bd_cmd update "$id"`, `bd_cmd update "$inc"`, `bd_cmd info --json`. All other `bd_cmd` stay.
3. In `do_submit`, on the line right after `wt_real` is assigned, add: `atom_root=$(ga_beads_root "$wt_real")`.
4. In `scan_repo`, on the line right after `repo=$(realpath "$repo")`, add: `atom_root=$(ga_beads_root "$repo")`.
5. Line with `"$ship_bin" "$wt" --atom` (~484): replace `env BEADS_ACTOR="$BEADS_ACTOR" "$ship_bin"` with `env BEADS_ACTOR="$BEADS_ACTOR" BEADS_DIR="${atom_root:-$SHIP_POST_BEADS_ROOT}/.beads" "$ship_bin"`.
6. Run `bash -n bin/ship-post`. Output: its rc and `git diff --stat`.
Forbidden: network, other files.
