# TZ — sdk-agent: stop holding the runs lock during the engine run (atom dcfg-p43q0)

Owner 17.10: the SDK tool must never paralyse other agents; one hand only (sdk), no second hand.
Fact: `bin/sdk-agent` `run_engine`: `flock "$lockfd"` (:158) → `check_daily_cap` (:159) → engine call `RESULT=$(... "$ENGINE" ...)` (:170) → `flock -u "$lockfd"` (:179). Every other sdk-agent call from any agent waits on the lock, with no timeout, until the running engine ends.
Transient API errors are already retried inside the engine (`CLAUDE_CODE_MAX_RETRIES` default 10, code.claude.com/docs/en/env-vars) — do not add a retry loop.
Reconnaissance — repowise (lead: `grep -n` on the named lines); index: repowise checked, CBM has no symbols for extension-less bash files.

## U1
FILE: bin/sdk-agent

1. Budget reservation. In-flight file = `"$RUNS_LOG.inflight"` (JSON lines `{"run_id":…,"ts":…,"budget":…}`; `ts` in the same format and day logic `check_daily_cap` already uses for runs.jsonl). `run_id` = `"$$-<epoch nanoseconds>"`.
2. `run_engine` new order:
   a. take the lock; `check_daily_cap "$budget"`; append this run's reservation to the in-flight file; release the lock;
   b. run the engine with NO lock held;
   c. take the lock again; append the result record to runs.jsonl exactly as today (record format unchanged); remove this run's reservation from the in-flight file (write a temp file in the same directory, then `mv`); release the lock;
   d. everything after (model guard rc 4, `RESULT`, `finish`) unchanged.
3. `check_daily_cap`: spent today = existing sum over runs.jsonl (unchanged, including "null cost counts as 2.00") + sum of `budget` of today's records in the in-flight file. Missing in-flight file = 0. A reservation left by a crashed run stays counted until the day ends — add one comment line: `# shortcut: a crashed run's reservation counts until midnight (fail-safe for money); upgrade: drop reservations whose pid is dead`.
4. Test-only engine override: when `SDK_AGENT_TEST=1` and `SDK_AGENT_ENGINE` is set, run that file instead of `$ENGINE`, and in that case do NOT source the key file and keep `ANTHROPIC_API_KEY` unset in the engine env (the override must never receive the key). Without `SDK_AGENT_TEST=1`, `SDK_AGENT_ENGINE` is ignored. Follow the existing pattern used for `SDK_AGENT_RUNS_LOG`.
5. Nothing else changes: model pin, budgets, DAILY_CAP, args, exit codes, `--help` text.

## U2
FILE: bin/sdk-agent-test

1. Near the top (after `export SDK_AGENT_TEST=1`), write a stub engine into `$TMP` with `printf` (it is created at test run time, not a repo file). The stub: sleeps `${STUB_SLEEP:-0}` seconds, then prints one line `{"type":"result","subtype":"success","total_cost_usd":0,"modelUsage":{"claude-haiku-5-5":{}},"result":"<key>"}` where `<key>` is `set` if `ANTHROPIC_API_KEY` is non-empty in its env, else `unset`; `chmod +x` it; `export SDK_AGENT_ENGINE` to it. Adjust the JSON fields only as needed so `run_engine` treats it as a success with model claude-haiku-5-5.
2. Add 3 checks with `check`, using a temp `SDK_AGENT_RUNS_LOG` each:
   - `"concurrent: two asks with a 3 s engine finish within 5 s"` — start two `ask --budget 0.5 hi` with `STUB_SLEEP=3` in the background, wait for both, both rc 0, wall time < 5 s (`date +%s` difference).
   - `"cap counts in-flight reservation: 4.60 reserved + 0.50 -> rc 6"` — write today's reservation `{"run_id":"x","ts":<today>,"budget":4.60}` to `<log>.inflight`, then `ask --budget 0.5 hi` → rc 6.
   - `"engine override never gets the API key"` — `ask --budget 0.5 hi` result contains `unset`; and with `env -u SDK_AGENT_TEST` the override is ignored (use the existing dry-args trick: `SDK_AGENT_DRY_ARGS=1` must still print the real engine path or not run the stub — pick the cheapest check that proves "ignored" without calling the real engine).
   - after each run the in-flight file holds no reservation of that run.
3. Existing checks unchanged in meaning; checks that reached the real engine under `SDK_AGENT_TEST=1` now reach the stub (that is intended).

## Edit paths
Every edit `path` is exactly `bin/sdk-agent` or `bin/sdk-agent-test`. Never an absolute path.

Lead check after the run (no Check line — the TZ edits the test file): `bin/sdk-agent-test` → `failed=0`; `bash -n` on both files → rc 0.

## Bans
No commit, no push, no new repo files, no other files. Do not read or print `.env`, secrets, `/root/workspaces/secrets/**`, `~/.ssh`, `/etc`, `auth.json`, the key file. Code principles: KISS, YAGNI, minimal diff, fail fast, no unrelated changes, no retry loops, no timers.
