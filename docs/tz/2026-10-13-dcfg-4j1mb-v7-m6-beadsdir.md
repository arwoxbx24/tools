# TZ dcfg-4j1mb v7 M6 — two-line fix, paste only, no exploration
Reason (real run 13.10): `cd` into a repo with its own `.beads` does not switch bd — from /root/workspaces/projects/clients/eurosteklo `bd where` prints /root/workspaces/projects/.beads and `bd show eurosteklo-re3` says not found; with `BEADS_DIR=/root/workspaces/projects/clients/eurosteklo/.beads bd show eurosteklo-re3` the atom is found. bd is selected by BEADS_DIR, not cwd.
File: `bin/ship-post` only.
1. Replace the two lines
```
bd_cmd(){ (cd "${atom_root:-$SHIP_POST_BEADS_ROOT}" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
bd_home(){ (cd "$SHIP_POST_BEADS_ROOT" && env BEADS_ACTOR="$BEADS_ACTOR" bd "$@"); }
```
with
```
bd_cmd(){ (cd "${atom_root:-$SHIP_POST_BEADS_ROOT}" && env BEADS_ACTOR="$BEADS_ACTOR" BEADS_DIR="${atom_root:-$SHIP_POST_BEADS_ROOT}/.beads" bd "$@"); }
bd_home(){ (cd "$SHIP_POST_BEADS_ROOT" && env BEADS_ACTOR="$BEADS_ACTOR" BEADS_DIR="$SHIP_POST_BEADS_ROOT/.beads" bd "$@"); }
```
2. Run `bin/ship-post-test` once. Output: FAIL lines, `checks=` line, `git diff --stat`. If a test fails only because its fake bd root has no `.beads` dir, report it; do not edit tests.
Forbidden: other files, network.
