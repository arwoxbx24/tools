# TZ dcfg-4j1mb — ship chain: per-repo Beads root, no-CI path, break-glass

Repo: this worktree (tools). Files you may edit: `bin/git-auto-lib`, `bin/ship`, `bin/ship-post`, `bin/ship-test`, `bin/ship-test.d/*`, `bin/ship-post-test`. Nothing else.
Reconnaissance: repowise / codebase-memory first, then `grep -n`, then Read only the ranges you edit. Index: repowise/CBM checked; missing → `tools/bin/code-memory-enable`.
Principles: SOLID, DRY, KISS, YAGNI, SoC, fail fast, least astonishment. Minimal diff, no refactors of untouched code, no new comments on unchanged code. Bash style of the existing files (tabs, `[[ ]]`, one-line helpers).
Forbidden: `rm -rf`, `git push` to real remotes, `gh` writes, network, editing `/etc`, `~/.ssh`, secrets, `.beads` data, hooks, CI workflows of this repo. Tests use temp dirs and local bare remotes only (follow the pattern of existing `bin/ship-test.d/*.sh` and `bin/ship-post-test`).
Output: short. Each failing test in full, passing ones as one summary line. End with `git diff --stat`.

## U1 — Beads DB per repository (AC1)
Problem (fact): `bin/ship-post:9` fixes `SHIP_POST_BEADS_ROOT=/root/workspaces/projects`, `bin/ship-post:77` `bd_cmd` always `cd`s there, `bin/ship:3` fixes `BEADS_DIR=/root/workspaces/projects/.beads`. Client repo `projects/clients/eurosteklo` has its own `.beads`; courier log repeats `Issue eurosteklo-re3 not found` every pass.
Do:
1. `bin/git-auto-lib`: add `ga_beads_root <path>` — main work tree of the repo containing `<path>` (`git rev-parse --path-format=absolute --git-common-dir`, parent dir), then walk up to `/`; first dir having a `.beads` directory wins; none → print `${SHIP_POST_BEADS_ROOT:-/root/workspaces/projects}`. Prints one absolute path, rc 0.
2. `bin/ship-post`: atom-level bd calls (show/update/close/reopen/label of the delivered atom: submit path, status of atom in scan, ack, park notes on the atom, final receipts notes) run in the atom's root = `ga_beads_root <worktree or repo>`. Incident create/update (`park_atom` incident id, line ~373–380) stays in `SHIP_POST_BEADS_ROOT`. Simplest form: `bd_cmd` reads a variable `atom_root` (default `SHIP_POST_BEADS_ROOT`) set where the repo/worktree is known; a separate `bd_home` for incidents.
3. `bin/ship-post` → `bin/ship` call: export `BEADS_DIR="$(ga_beads_root <wt>)/.beads"` for that call. `bin/ship:3` keeps its default only when `BEADS_DIR` is unset.
4. Unknown atom (bd show says not found in its own root): write one final receipt `unknown-atom` for that SHA and log one line; next passes skip it (no 30 s loop). `ship-post --status` prints `unknown-atom`.
Check: new case in `bin/ship-post-test`: temp repo with its own `.beads` stub dir + fake `bd` on PATH that records its cwd → atom calls happen in the repo root, incident calls in `SHIP_POST_BEADS_ROOT`; unknown atom → one receipt, second pass no bd show.

## U2 — No CI: add minimal CI instead of the wait-owner dead end (AC2)
Problem (fact): `bin/ship:136-178` — no `pull_request` workflow and mode `two` → `prod:wait-owner no-ci`, stop. `bin/git-ci-enable <worktree>` already writes a minimal CI workflow.
Do:
1. In `bin/ship`, when `ci == none` and the diff is not docs-only (keep the existing docs-only path), before push: run `"$bin/git-ci-enable" "$wtr"`, commit the added workflow in the same branch through the same gitleaks + commit path (trailers Atom/ТЗ/Agent), set `ci=ci`, continue the normal CI path. `git-ci-enable` failure → `leave 30 ci-enable` with its stderr line.
2. `prod:wait-owner no-ci` output disappears; production gate (`ship-promote`, `prod:hold guarded`) unchanged.
3. `bin/ship-post` scan: a final receipt with stage `wait-owner` whose ship log contains `prod:wait-owner no-ci` is re-run through `ship` once (like the existing legacy `'wait-owner no-ci'` branch near line 547), then a normal receipt is written.
Check: new `bin/ship-test.d/` case: repo without workflows, code change → branch contains `.github/workflows/*`, no `wait-owner no-ci` in output; docs-only change still `gate:auto docs-only`.

## U3 — `ship-post --break-glass <worktree> --atom <id>` (AC3)
Purpose: the agent keeps working when the courier is broken for its SHA. Machine-gated, audited, never weaker than normal delivery.
Do:
1. Allowed only if a `*.failed` receipt exists for this repo/atom/HEAD SHA with ship code 30, 70, 71 or 75 (INFRA). Otherwise exit 2: `ship-post: break-glass refused: no recorded INFRA failure for <sha>; run ship-post --status <atom>`.
2. Same checks as `--submit` for owner/assignee and worktree root; then `gitleaks git --redact --no-banner --log-opts "origin/<base>..HEAD"`; leak → exit 20 `break-glass refused: gitleaks`.
3. File the incident in `SHIP_POST_BEADS_ROOT`: `bd create "[ship-post] break-glass <atom> <sha>" -t bug -p 0 -l contour:delivery,break-glass` with description: failed rc, last error line, receipt log path, worktree, branch, and `## Steps to Reproduce` + `## Fix spec` (courier must deliver this SHA itself; break-glass use is a defect). Print `incident=<id>`.
4. Push the branch with lease to `origin` (same refspec form as `bin/ship` lines 115–119) and print `direct=pushed`; if `gh` is available and origin is GitHub, open a PR if none exists (`gh pr create --fill --head <branch>`), print `pr=<url>`; else print `pr=skipped`. No merge, no bd close, no live sync: merge stays with CI and the courier.
5. Write a receipt line `break-glass` for the SHA; append a note to the atom: `break-glass used: incident <id>`.
6. Add `--break-glass` to the help text.
Check: new case in `bin/ship-post-test` with a local bare remote: (a) no failed receipt → exit 2; (b) planted fake AWS key `AKIA` + 16 chars in a commit → exit 20; (c) clean commit after recorded rc 30 → prints `incident=`, `direct=pushed`, bare remote has the branch.

## Done
`bin/ship-post-test` and `bin/ship-test` exit 0; `git diff --stat` shows only the allowed files.
