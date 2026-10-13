# TZ dcfg-4j1mb v7 M4 — two-line fix, paste only
Reason: after merge, `do_break_glass` does not set `atom_root`, so an atom from a repo with its own `.beads` (eurosteklo) is looked up in the wrong Beads root; the incident must go to the home root like INFRA incidents.
File: `bin/ship-post`, function `do_break_glass` only.
1. Directly before the line `atom_json=$(bd_cmd show "$atom" --json 2>/dev/null) || usage_err "bd show $atom failed"` add (tab indent):
```
	atom_root=$(ga_beads_root "$wt_real")
```
2. In the line `incident=$(bd_cmd create "[ship-post] break-glass $atom $head_sha" ...`, change `bd_cmd create` to `bd_home create`. Nothing else.
3. In `bin/ship-post-test`, if the fake bd used by `test_break_glass` records calls in `bd.calls`, no change is needed; run `SHIP_POST_TEST_GROUP=all bin/ship-post-test` once. Output: failures, `checks=` line, `git diff --stat`.
Forbidden: other files, network.
