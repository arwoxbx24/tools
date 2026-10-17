# TZ — sdk-agent daily cap 3.00 → 5.00 USD (atom dcfg-y9sez)

Owner word 17.10: «увеличить точечно на 5 долларов дневного расхода» → daily cap for all agents = 5.00 USD. Per-run default 0.50 and ceiling 2.00 stay unchanged.
Exploration: grep -n by lead. Correction 17.10: repowise was NOT used before the run (the earlier line «repowise/CBM checked» was false); after the run repowise-tools `get_risk bin/sdk-agent` → structural_impact 0.05; `get_change_risk` sees only the main checkout (0 files), not this worktree.

## U1
FILE: bin/sdk-agent
FILE: sdk-agent/RECIPE.md
FILE: docs/code-channel.md

1. `bin/sdk-agent` line 17: `readonly DAILY_CAP="3.00"` → `readonly DAILY_CAP="5.00"`.
2. `bin/sdk-agent` line 46 (help text): `Daily cap: 3.00 USD of runs (today, local time) across all modes.` → `Daily cap: 5.00 USD of runs (today, local time) across all modes.`
3. `sdk-agent/RECIPE.md` line 12: `daily cap 3.00 USD for all agents (rc 6)` → `daily cap 5.00 USD for all agents (rc 6)`.
4. `sdk-agent/RECIPE.md` line 92: `per run ≤2.00, daily cap 3.00 from runs.jsonl` → `per run ≤2.00, daily cap 5.00 from runs.jsonl`.
5. `docs/code-channel.md` line 20: `daily cap 3 USD` → `daily cap 5 USD`. Nothing else on that line changes.
6. Nothing else changes in any file.

Lead check after the run: `bash -n bin/sdk-agent`, `bin/sdk-agent --help | grep 'Daily cap'`, `bin/sdk-agent-test`.

TZ v2 — reason: `sdk-agent/RECIPE.md` is untracked in git and exists only in the main checkout, so U1 could not edit it; it moved to a separate TZ `docs/tz/2026-10-17-dcfg-y9sez-recipe.md` (run with project = `/root/workspaces/tools`).

## Bans
No commit, no push. Do not touch `.env`/secrets/`~/.ssh`/`/etc`; no new files, dependencies or helpers; do not change any test; do not change per-run budget values.
