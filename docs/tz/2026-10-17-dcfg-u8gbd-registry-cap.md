# TZ — TOOLS-REGISTRY.md: sdk-agent daily cap 3.00 → 5.00 USD (atom dcfg-u8gbd)

Owner word 17.10: daily cap for all agents = 5.00 USD; code already changed in PR tools#294 (`bin/sdk-agent:17 DAILY_CAP="5.00"`). The registry row was missed.
Exploration: repowise-tools search_codebase + get_context (statusline file) by lead; `git grep -n 'cap 3.00'` → `TOOLS-REGISTRY.md:26` only (tracked, non-TZ).

## U1
FILE: TOOLS-REGISTRY.md

1. Line 26: `daily cap 3.00 USD for all agents (rc 6)` → `daily cap 5.00 USD for all agents (rc 6)`.
2. Nothing else changes.

Lead check after the run: `git grep -c 'daily cap 5.00' TOOLS-REGISTRY.md` → 1; `git grep -c 'daily cap 3.00' TOOLS-REGISTRY.md` → 0.

## Bans
No commit, no push. Only the listed file. Do not touch `.env`/secrets/`~/.ssh`/`/etc`; no new files.
