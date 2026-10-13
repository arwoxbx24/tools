# TZ dcfg-4j1mb v4 — W-A2: ship-post --break-glass (U3)

v4 reason: owner 13.10 asked for more parallelism. Another worker edits bd root handling in `bin/ship-post` (function `bd_cmd` and its call sites) — do NOT change `bd_cmd` or existing call sites; add new code in a new function `do_break_glass` plus the argument-parsing and help-text lines it needs, so the two branches merge cleanly. Use existing `bd_cmd` for bd calls (incidents go to `SHIP_POST_BEADS_ROOT`).
Source of truth: section U3 of /root/workspaces/projects/.worktrees/claude/tools-dcfg-4j1mb/docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md.
Files you may edit: `bin/ship-post`, `bin/ship-post-test` (add a new test block at the end only).
Speed: no baseline suite run. Implement, run `bin/ship-post-test` once at the end. Output: failures in full, passes one line, then `git diff --stat`.
Reconnaissance: repowise/codebase-memory, `grep -n`, Read only ranges you edit. No network, no real remotes (local bare repo in a temp dir), no `rm -rf` outside temp dirs.
