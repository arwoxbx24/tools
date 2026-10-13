# TZ dcfg-4j1mb v3 — W-A: ship-post + git-auto-lib (U1, U2.3, U3)

v3 reason: owner 13.10 asked to split by file for parallel workers. Source of truth for behaviour: `docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md` (absolute: /root/workspaces/projects/.worktrees/claude/tools-dcfg-4j1mb/docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md) sections U1, U2 item 3, U3.
Files you may edit: `bin/git-auto-lib`, `bin/ship-post`, `bin/ship-post-test`. NOT `bin/ship` (another worker owns it): `bin/ship:3` already honours an exported `BEADS_DIR`, so U1 item 3 = export `BEADS_DIR` in ship-post before calling ship.
Speed: do NOT run the whole suite first. Implement, then run only `bin/ship-post-test` once at the end. Output: failures in full, passes one line, then `git diff --stat`.
Reconnaissance: repowise/codebase-memory, `grep -n`, Read only ranges you edit. Principles and forbidden list as in the source TZ.
