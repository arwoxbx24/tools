# TZ dcfg-4j1mb v4 — W-A1: per-repo Beads root (U1, U2 item 3)

v4 reason: owner 13.10 asked for more parallelism; break-glass (U3) moved to another worker. Do NOT implement U3 and do not touch argument parsing or help text of `bin/ship-post`.
Source of truth: sections U1 and U2 item 3 of /root/workspaces/projects/.worktrees/claude/tools-dcfg-4j1mb/docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md.
Files you may edit: `bin/git-auto-lib`, `bin/ship-post`, `bin/ship-post-test`. NOT `bin/ship` (`bin/ship:3` already honours an exported `BEADS_DIR`; export it in ship-post before calling ship).
Speed: no baseline suite run. Implement, run `bin/ship-post-test` once at the end. Output: failures in full, passes one line, then `git diff --stat`.
Reconnaissance: repowise/codebase-memory, `grep -n`, Read only ranges you edit. Principles and forbidden list as in the source TZ.
