# TZ dcfg-4e14l U1 — test runs_log_ignored_without_test_flag must not call the paid engine

Atom: dcfg-4e14l · discovered from dcfg-pkzcf (review finding HIGH, confirmed by the lead in the live ledger).
FILE: bin/sdk-agent-test
FILE: docs/tz/2026-10-17-dcfg-4e14l-test22-nopaid.md

## Fact
`bin/sdk-agent-test:110` function `runs_log_ignored_without_test_flag` runs `env -u SDK_AGENT_TEST … ask --budget 0.5 …`: without SDK_AGENT_TEST the wrapper takes the non-test branch (real engine, API key), so every suite run makes a real paid call and appends to the live `tools/sdk-agent/runs.jsonl` (4 such entries measured 17.10). Its assertion (rc != 6, no "daily cap" text) also passes on rc 3 "key file missing", so it does not prove its name. Check line `bin/sdk-agent-test:336` stays as is.

## Required
Rewrite only the body of `runs_log_ignored_without_test_flag` (ADR 17.10: the one allowed change of existing test lines — the old body spends money; the new one is stricter). New body proves "SDK_AGENT_RUNS_LOG is ignored without SDK_AGENT_TEST" with the read-only `sdk-agent cap --json` (no engine, no key, writes nothing): write a temp fake runs log whose today spend is a distinctive value (e.g. one line `{"ts":<now>,"total_cost_usd":3.33}`), run `env -u SDK_AGENT_TEST -u SDK_AGENT_TEST_CAP SDK_AGENT_RUNS_LOG=<fake> "$ag" cap --json`, assert rc 0 and that `.spent` is NOT 3.33 (the live ledger was read, not the fake); then, as a control, the same command WITH `SDK_AGENT_TEST=1` must report `.spent` == 3.33. Never call `ask`/`code`/`read` without SDK_AGENT_TEST anywhere in the suite. Nothing else changes.
Разведка — repowise / grep -n; edit only the FILE paths above. No secrets in output.

## Done-check (lead)
`wc -l < tools/sdk-agent/runs.jsonl` equal before and after `bash bin/sdk-agent-test`; suite last line `PASS all`; `git diff origin/main --numstat -- bin/sdk-agent-test` deleted lines only inside that function.
