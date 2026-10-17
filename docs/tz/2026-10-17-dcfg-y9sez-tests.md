# TZ v3 (U3) — sdk-agent-test fixtures for daily cap 5.00 (atom dcfg-y9sez)

Reason: after U1 (`DAILY_CAP` 3.00 → 5.00, owner 17.10) three tests fail because their fixtures encode the old cap 3.00: `not ok 14: daily cap refuses ask (rc 6)`, `not ok 24: cap boundary: 2.51 + 0.50 -> rc 6`, `not ok 25: cap: null cost counts as 2.00`. The tests keep the same meaning; only the numbers move to the new boundary (spent + budget 0.50 > 5.00 → rc 6).
Exploration: grep -n and Read by lead. Correction 17.10: repowise was NOT used before the run (the earlier line «repowise/CBM checked» was false).

## U3
FILE: bin/sdk-agent-test

1. Line 67 (`daily_cap_refuses`): `"total_cost_usd":1.5}\n{"ts":%s,"total_cost_usd":1.5}` → `"total_cost_usd":2.5}\n{"ts":%s,"total_cost_usd":2.5}` (5.0 + 0.5 > 5.00 → rc 6).
2. Line 114 (`cap_boundary_under_not_refused`): `"total_cost_usd":2.50` → `"total_cost_usd":4.50` (4.50 + 0.50 = 5.00, not over → not refused).
3. Line 123 (`cap_boundary_over_refused`): `"total_cost_usd":2.51` → `"total_cost_usd":4.51` (5.01 > 5.00 → rc 6).
4. Line 130 (`cap_null_cost_counts_as_ceiling`): `"total_cost_usd":0.60` → `"total_cost_usd":2.60` (null counted as 2.00: 2.00 + 2.60 + 0.50 = 5.10 → rc 6; if null were 0 the sum 3.10 would pass, so the test still discriminates).
5. Line 205 label: `cap boundary: 2.50 + 0.50 not refused` → `cap boundary: 4.50 + 0.50 not refused`.
6. Line 206 label: `cap boundary: 2.51 + 0.50 -> rc 6` → `cap boundary: 4.51 + 0.50 -> rc 6`.
7. Line 207 label stays `cap: null cost counts as 2.00`.
8. Nothing else changes; no test is removed, skipped or weakened; line 105 (`10.0`, test without the test flag) stays.

Lead check after the run: `bin/sdk-agent-test` → no `not ok` lines, rc 0.

## Bans
No commit, no push. Only the listed file. Do not touch `.env`/secrets/`~/.ssh`/`/etc`; no new files or helpers.
