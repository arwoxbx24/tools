# TZ dcfg-4j1mb v9 — Beads root fallback + code-channel-test model (PR 252 CI fail #2)
Discovery: repowise / grep -n; read only the ranges you edit.
Files: `bin/ship-post`, `bin/ship-post-test`, `bin/code-channel-test` only. KISS, minimal diff, keep messages and exit codes.
Forbidden: `git stash`, `git checkout`, `git reset`, `git restore`, `git add`, `git commit`, `git merge`, other files, network, running `bin/ship-post` outside its test (never against `/root/workspaces/tools/state`).

## U1 — Beads root fallback (proven defect)
Repro: `/root/workspaces/tools/.beads` exists (Codex `tools-*` atoms) while `dcfg-*` atoms live in `/root/workspaces/projects/.beads`. `ga_beads_root /root/workspaces/tools` → `/root/workspaces/tools`; `BEADS_DIR=/root/workspaces/tools/.beads bd show dcfg-4j1mb.5 --json` → "Issue dcfg-4j1mb.5 not found". So every `dcfg-*` atom of the tools repo becomes `unknown-atom` and is never delivered; `--submit` and `--break-glass` refuse with "bd show … failed".
Fix in `bin/ship-post` (one shared place, DRY): add `resolve_atom_root(){ # <path> <atom> — nearest Beads root holding <atom>, else SHIP_POST_BEADS_ROOT` that sets global `atom_root=$(ga_beads_root "$1")`, then if `atom_root != SHIP_POST_BEADS_ROOT` and `bd_cmd show "$2" --json` output/err contains `not found`, sets `atom_root=$SHIP_POST_BEADS_ROOT`. Replace every `atom_root=$(ga_beads_root …)` in `bin/ship-post` (in `check_agent_worktree`, `scan_repo`, and any other) with a call `resolve_atom_root <same path> "$atom"`. If an atom is not found in either root, behavior stays as now (unknown-atom / usage_err).
Test in `bin/ship-post-test` (existing style, one case): repo with its own `.beads` dir whose mock bd reports "not found" for the atom, atom present in `SHIP_POST_BEADS_ROOT` → delivered (ship called once), no `unknown-atom` receipt. If the mock bd cannot tell roots apart, extend the mock minimally via `BEADS_DIR` and say how.

## U2 — `bin/code-channel-test` case 22
CI: `FAIL 22: rc=0 out=go opencode-go/deepseek-v4.1-flash - audit=opencode-go/longcat-2.5-preview-free …`. Owner 13.10 switched the go model in `config/code-channel.json` to `opencode-go/deepseek-v4.1-flash`. Update only the expected model string(s) of case 22 (and any other case that hardcodes `glm-5.3-flash` as the configured go model) to `opencode-go/deepseek-v4.1-flash`. Do not change `config/code-channel.json`.

## Run once
`bin/ship-post-test 2>&1 | grep -E '^FAIL|checks='`, `bin/code-channel-test 2>&1 | grep -E '^FAIL' ; echo rc=$?` style (show FAIL lines and the final count), `npx --yes jscpd@5.4.1 --baseline-from-ref origin/main --fail-on-new-clones=0 bin scripts | tail -n 3`, `git diff --stat`.
