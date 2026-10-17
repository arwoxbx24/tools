# TZ — sdk-agent: prompt cache always on, cache counters back in runs.jsonl (atom dcfg-squ11)

Owner 17.10: platform cache hit dropped ~50%; "жёстко внедрить ... системный механизм, чтобы ни один агент не смог работать без кэширования".
sdk-agent is the only route to the paid API, so the guarantee lives in `bin/sdk-agent` and its test.
Reconnaissance — repowise (repowise-tools search_codebase/get_context by lead) + `grep -n`; index: repowise checked.

## Sources
- code.claude.com/docs/en/cli-reference, `--exclude-dynamic-system-prompt-sections`: "Move per-user context, such as the auto memory location, out of the system prompt and into the first user message. Improves prompt-cache reuse across different users and machines running the same task. ... Use with `-p` for scripted, multi-user workloads".
- code.claude.com/docs/en/agent-sdk/modifying-system-prompts, "Improve prompt caching across users and machines": "two sessions that use the same `claude_code` preset ... still can't share a prompt cache entry when their auto memory locations differ ... The location defaults to an absolute path under `~/.claude/projects/` named for the repository's path on disk, so it differs across users, machines, and checkouts."
- Fact: `bin/sdk-agent:167` runs the engine with `cd -- "$workdir"` (a different worktree/clone each run); `sdk-agent/engine-home/projects/` holds 4 per-directory folders.
- Fact: `bin/sdk-agent:171` logs only `subtype,total_cost_usd,ts,mode,models`; `sdk-agent/RECIPE.md:47` cache report reads `.usage.*` → null since 16.10 10:42.

## U1
FILE: bin/sdk-agent

1. In `run_engine`, the args array built at line 149 (`args+=(--no-session-persistence --output-format json)`) also gets `--exclude-dynamic-system-prompt-sections` — on every run, every mode (ask, read, code). No option or env var may switch it off.
2. Dry-args mode (TZ v4 — no engine or key override anywhere: a swapped engine would receive the real key and skip the model pin and daily cap). Only when `SDK_AGENT_TEST=1` and `SDK_AGENT_DRY_ARGS=1`: `run_engine` prints the built `args` array, one element per line, to stdout and exits 0 right after the args are built (before the flock, the daily cap, the key file check and any engine call). `ENGINE` and `KEY_FILE` stay fixed `readonly` paths with no override.
3. The runs.jsonl record (jq at lines 170-171) becomes:
   `{subtype, total_cost_usd, ts: $ts, mode: $mode, models: ((.modelUsage // {}) | keys), workdir: $workdir, usage: ((.usage // {}) | {input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens})}` with `--arg workdir "$workdir"`.
4. `finish()` stderr line becomes `sdk-agent: subtype=%s cost_usd=%s cache_read=%s cache_write=%s` (values from `.usage.cache_read_input_tokens // "null"` and `.usage.cache_creation_input_tokens // "null"`).
5. Update the comment at line 137 to name the new logged fields. Nothing else changes.

## U2
FILE: bin/sdk-agent-test

Add one check function and its `check` line (offline, no key, no network), following the existing style:
1. Run `env SDK_AGENT_DRY_ARGS=1 SDK_AGENT_RUNS_LOG=$TMP/runs-dry.jsonl "$ag" ask --budget 0.5 hi` and capture stdout.
2. Pass only when: rc 0; stdout has the line `--exclude-dynamic-system-prompt-sections`; `$TMP/runs-dry.jsonl` does not exist (nothing logged, no engine run).
3. Second function: `env -u SDK_AGENT_TEST SDK_AGENT_DRY_ARGS=1 ...` must NOT print the args (dry mode ignored without SDK_AGENT_TEST=1): pass when stdout lacks `--exclude-dynamic-system-prompt-sections`. Run it with a non-writable `SDK_AGENT_RUNS_LOG` is not possible there (ignored), so give it `--budget 9` → rc 2 refusal before any engine call.
Check line texts: `check "dry args: engine always gets --exclude-dynamic-system-prompt-sections" <fn1>` and `check "dry args ignored without SDK_AGENT_TEST" <fn2>`.
The cache counters in runs.jsonl are verified by the lead's live run (criterion 4), not offline.

## U3
FILE: sdk-agent/RECIPE.md

1. Line 106 (`--exclude-dynamic-system-prompt-sections` under "Not used, on purpose"): remove it from that list.
2. In the flags table near line 40, add a row: `` | `--exclude-dynamic-system-prompt-sections` | Always on (owner 17.10, dcfg-squ11): the auto memory path differs per worktree/clone and broke the shared prompt cache; doc: code.claude.com/docs/en/agent-sdk/modifying-system-prompts. | ``
3. Line 47 report stays valid (records again carry `.usage`); add after it one line: `Records from 2026-10-16 10:42 until dcfg-squ11 have no usage (counters were not logged).`

Lead check after the run: `bash bin/sdk-agent-test` → all PASS (TZ v2: no Check line — the TZ edits that test, wrapper rule dcfg-kj836).

## Edit paths (TZ v3)
Every edit `path` must be exactly the repo-relative path as listed: `bin/sdk-agent`, `bin/sdk-agent-test`, `sdk-agent/RECIPE.md`. Never an absolute path (v2 run: absolute path → `refused model path`, rc 5).

## Bans
No commit, no push, no new files beyond the listed ones. Do not read or print `.env`, secrets, `/root/workspaces/secrets/**`, `~/.ssh`, `/etc`, `auth.json`. Do not run the real engine or the real key. Code principles: KISS, YAGNI, minimal diff, no unrelated changes.
