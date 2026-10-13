# TZ dcfg-4j1mb v3 — W-B: ship no-CI path (U2 items 1–2)

v3 reason: owner 13.10 asked to split by file for parallel workers. Source of truth: section U2 items 1–2 of /root/workspaces/projects/.worktrees/claude/tools-dcfg-4j1mb/docs/tz/2026-10-13-dcfg-4j1mb-ship-chain.md.
Files you may edit: `bin/ship`, `bin/ship-test`, `bin/ship-test.d/*` (new case file allowed). NOT `bin/ship-post`, `bin/git-auto-lib`, `bin/git-ci-enable` (other workers).
Facts: `bin/ship:136-178`. Remove the `wait-owner no-ci` stop at lines 173-178 and the mode-two `ci-none` refusal at 152-155: when `ci == none` and `docs_only == 0`, before push run `"$bin/git-ci-enable" "$wtr"` (prints `ci:added <path>` or `ci:present`), stage and commit the added file through the same gitleaks + commit path with trailers Atom/ТЗ/Agent, set `ci=ci`, continue the normal CI path. Failure → `leave 30 ci-enable`. Docs-only path, guarded `prod:hold`, ship-promote unchanged. Note: the no-CI decision must happen before push (move it above the push if it is below).
Test: a ship-test.d case — repo without workflows + non-md change → branch has `.github/workflows/*`, output has no `wait-owner no-ci`; docs-only still `gate:auto docs-only`. In tests stub `git-ci-enable` only if the real one needs network (it does not).
Speed: do NOT run the whole suite first. Implement, then run `bin/ship-test` once at the end. Output: failures in full, passes one line, then `git diff --stat`.
Reconnaissance: repowise/codebase-memory, `grep -n`, Read only ranges you edit. No network, no real remotes, no `rm -rf` outside temp dirs.
