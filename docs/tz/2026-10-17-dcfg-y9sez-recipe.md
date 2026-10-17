# TZ v2 (U2) — RECIPE.md daily cap 3.00 → 5.00 USD (atom dcfg-y9sez)

Reason: `sdk-agent/RECIPE.md` is untracked in git and exists only in the main checkout `/root/workspaces/tools`; run with project = `/root/workspaces/tools`.
Exploration: grep -n by lead. Correction 17.10: repowise was NOT used (the earlier line «repowise/CBM checked» was false).
Result: `sdk-agent code` refused the path (`refused model path: /root/workspaces/tools/sdk-agent/RECIPE.md`, code-channel rc 5); the file is MD, so the lead edited lines 12 and 92 with Edit after a backup `projects/.agent-work/backup/RECIPE.md.dcfg-y9sez.20261017`.

## U2
FILE: sdk-agent/RECIPE.md

1. Line 12: `daily cap 3.00 USD for all agents (rc 6)` → `daily cap 5.00 USD for all agents (rc 6)`.
2. Line 92: `per run ≤2.00, daily cap 3.00 from runs.jsonl` → `per run ≤2.00, daily cap 5.00 from runs.jsonl`.
3. Nothing else changes.

## Bans
No commit, no push. Only the listed file. Do not touch `.env`/secrets/`~/.ssh`/`/etc`; no new files.
