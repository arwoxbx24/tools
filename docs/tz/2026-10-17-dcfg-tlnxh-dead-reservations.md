# TZ dcfg-tlnxh U1 — sdk-agent: dead in-flight reservations, orphan engines, read-only cap

Atom: dcfg-tlnxh · Epic: dcfg-aw1i7 · Spec: projects specs/110-sdk-cap-guard-fixes (FR-001..003a, SC-001/002, US1)
FILE: bin/sdk-agent
FILE: bin/sdk-agent-test
FILE: docs/tz/2026-10-17-dcfg-tlnxh-dead-reservations.md

## Goal
The daily cap and its read-only view count: completed spend + live reservations + aborted runs (real cost or budget as upper bound). A reservation of a run whose wrapper died stays counted while its engine still runs; once nothing of the run lives, it is folded into the ledger exactly once.

## Facts (verified 17.10)
- `run_engine` (bin/sdk-agent) writes the in-flight line `{run_id: "$$-<ns>", ts, budget}` under `$RUNS_LOG.lock`, then runs the engine inside `RESULT=$(…)` with no trap; normal end removes the line. `die "engine returned no JSON result" 4` exits without removing it.
- `check_daily_cap` adds every in-flight `.budget` with ts >= local midnight; comment line starts `# shortcut: a crashed run's reservation counts until midnight`.
- Live file now: 3 lines, all pids dead (`/proc/<pid>` absent).

## Required behaviour
1. In `run_engine`, after the in-flight line is written and before the engine starts: create `$RUNS_LOG.inflight.d/` if missing; open `$RUNS_LOG.inflight.d/<run_id>.lock` on a new fd and take `flock` on it (held for the life of the run; the engine child inherits the fd, so an engine that outlives the wrapper keeps it locked). The engine's stdout goes to `$RUNS_LOG.inflight.d/<run_id>.out`; RESULT is then read from that file (behaviour of RESULT unchanged). On normal end remove both files together with the in-flight line.
2. New function `fold_dead_reservations` (called under `$RUNS_LOG.lock`, before the cap check inside `run_engine`): for each in-flight line, dead = (`.lock` file exists and `flock -n` on it succeeds) OR (no `.lock` file AND the run_id prefix before `-` is all digits AND `/proc/<pid>` does not exist). Otherwise alive. For each dead line: append to `$RUNS_LOG` one line `{subtype:"aborted", mode:"aborted", run_id, ts:<line ts>, budget, total_cost_usd:<.total_cost_usd of the .out JSON if it is a number, else budget>, cost_source:"result"|"upper-bound", models:[], workdir:"", usage:{}}`, drop the line from the in-flight file (same mktemp+mv pattern as today), remove its `.lock`/`.out`.
3. One computation `cap_state` (read-only, no lock, no writes) returning JSON `{cap, spent, reserved, aborted, aborted_bound, left}` for today (ts >= local midnight): spent = sum of ledger `(.total_cost_usd // MAX_BUDGET)` (as today); reserved = budgets of alive in-flight lines; aborted/aborted_bound = count/budget sum of dead in-flight lines not yet folded; left = max(0, cap − spent − reserved − aborted_bound). Numbers rounded to 2 decimals in output.
4. `check_daily_cap BUDGET` uses `cap_state` and refuses (exit 6, same message form `refused: daily cap <cap> USD (spent <spent+reserved+aborted_bound> today)`) when that sum + BUDGET > cap.
5. New subcommand `sdk-agent cap --json`: prints `cap_state` JSON, rc 0, writes nothing; add it to `--help` (one line). No engine, no key load.
6. Replace the `# shortcut:` comment by one line stating the new rule.

## Tests (bin/sdk-agent-test, add only; no engine call; use SDK_AGENT_TEST fixtures and a temp RUNS_LOG as the existing cases do)
- `dead_pid_reservation_not_counted`: in-flight line with run_id `999999999-1` (pid absent), `.lock` absent, plus a `.out` file is ignored for legacy → expect folded with cost_source upper-bound; AND a second line with a `.lock` nobody holds and `.out` `{"total_cost_usd":0.03}` → folded with 0.03, cost_source result; after the fold the in-flight file has 0 lines and `cap --json` shows reserved 0. Print exactly `PASS dead_pid_reservation_not_counted`.
- `orphan_engine_keeps_reservation`: a background `flock <lock> sleep 30`-style holder (killed at the end of the case) holds the `.lock` → reservation stays counted, no ledger line. Print `PASS orphan_engine_keeps_reservation`.
- `cap_json_readonly`: `sha256sum` of RUNS_LOG and in-flight file equal before/after `sdk-agent cap --json`; rc 0; output has keys cap,spent,reserved,aborted,aborted_bound,left. Print `PASS cap_json_readonly`.
- The suite's last line stays the existing final PASS line.

## Constraints
- Minimal code, KISS/YAGNI, bash + jq + flock only; no new dependency; keep existing behaviour of every other path; do not delete or weaken any existing test line.
- Do not touch the live `tools/sdk-agent/runs.jsonl*` files in tests.
- Разведка — repowise (индекс tools); edit only the FILE paths above.
- No secrets in output; never print the key file.

## v2 (17.10) — pre-existing suite failures
Fact: `bash bin/sdk-agent-test` on origin/main → `ok 31/36`, on this branch → `ok 34/39`; same 5 cases fail on both: 14 `daily cap refuses ask (rc 6)`, 22 `SDK_AGENT_RUNS_LOG ignored without SDK_AGENT_TEST`, 24 `cap boundary: 4.51 + 0.50 -> rc 6`, 25 `cap: null cost counts as 2.00`, 33 `cap counts in-flight reservation: 4.60 reserved + 0.50 -> rc 6`. Hypothesis: owner raised `DAILY_CAP` to 6.00 (commit 454112e, dcfg-ghs1r) and the fixtures still assume 5.00; case 22 — find its own cause.
Required: find the root cause of each of the 5 failures and make the whole suite pass (last line PASS). Keep the cap 6.00 (owner order). Do not delete or weaken any assertion; test-file changes add lines only (e.g. a test-only cap override honoured only when `SDK_AGENT_TEST` is set, or new fixture values on added lines). Keep the 3 new cases passing.

## v3 (17.10) — product cap is now 7.00
Fact: owner raised the cap to 7.00 (PR #324, dcfg-aw1i7.3); the branch is now on origin/main 0f6292b, and `git diff origin/main -- bin/sdk-agent` shows this branch setting `readonly DAILY_CAP="6.00"` (non-test branch) and help text `Daily cap: 6.00 USD`, i.e. it would revert the owner's 7.00.
Required (supersedes "Keep the cap 6.00" in v2): in `bin/sdk-agent` the non-test `DAILY_CAP` = `7.00` and the help line says `Daily cap: 7.00 USD of runs (today, local time) across all modes.`; keep the test override `SDK_AGENT_TEST_CAP` as is. In `bin/sdk-agent-test` the case `cap_default_six` must assert 7 (rename to `cap_default_seven`, its check text "cap default daily cap is 7.00 (no test override)") and the comment line above `export SDK_AGENT_TEST_CAP=5.00` must say the cap is 7.00 (owner, dcfg-aw1i7.3). Nothing else.

## Done-check (run by the lead, not by the hand)
`bash bin/sdk-agent-test` → contains `PASS dead_pid_reservation_not_counted`, last line PASS; `git diff origin/main --numstat -- bin/sdk-agent-test` → 0 deleted lines.
