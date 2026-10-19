# TZ U1 — sdk-agent ledger records the TZ path (atom dcfg-nl951)

Goal: every entry appended to `runs.jsonl` carries a `tz` field with the TZ file path given on the command line (code/read modes), so a run is tied to its TZ by a ledger field. `ask` and `aborted` entries carry `tz: ""`.

FILE: bin/sdk-agent
FILE: bin/sdk-agent-test

## bin/sdk-agent
1. In the function that appends the result entry (the `jq -c --argjson ts "$(date +%s)" --arg mode "$mode" --arg workdir "$workdir"` call whose object is `{subtype, total_cost_usd, ts: $ts, mode: $mode, models: ..., workdir: $workdir, usage: ...}`): add `--arg tz "${TZ:-}"` and the key `tz: $tz` right after `workdir: $workdir`. `TZ` is the global set from the positional argument (`TZ=${POS[1]}`) in code/read modes; in ask mode it is unset, so `${TZ:-}` gives "".
2. In the `aborted` entry (`'{subtype: "aborted", mode: "aborted", run_id: $id, ts: $ts, budget: $budget, total_cost_usd: $cost, cost_source: $src, models: [], workdir: "", usage: {}}'`): add `tz: ""` after `workdir: ""`.
3. Update the comment line above the append function that lists the fields (`# (subtype, cost, ts, mode, models, workdir, usage: ...) to runs.jsonl`) to include `tz`.
4. No other change. Do not touch MODEL, budgets, caps, lock or key handling.

## bin/sdk-agent-test
5. Add one check function `ledger_records_tz` modelled on the existing read stub test (the one that runs `env SDK_AGENT_ENGINE="$stub_stdin" ... "$ag" read "$TMP/wt" "$tz"` with its own `log`): after the read run, assert `[[ $(tail -1 "$log" | jq -r '.tz') == "$tz" ]]`. Register it with `check "ledger entry records tz of the read run" ledger_records_tz` next to the other `check` lines. Reuse the existing stub engine and fixtures; create nothing new outside `$TMP`.
6. Keep every existing check unchanged.

Principles: KISS, YAGNI, minimal diff, no refactor of neighbouring code, no new helpers.
Done when: `git diff --stat` shows only the two listed files; `bin/sdk-agent-test` passes with the new check (run by the lead, not by you).
