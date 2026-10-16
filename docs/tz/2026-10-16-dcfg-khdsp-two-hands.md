# TZ dcfg-khdsp.1 — two hands behind one entry (owner 16.10, approved scheme)

Owner 16.10: two main executors — `sdk-agent` (Claude SDK, priority now) and OpenCode Go (subscription, model DeepSeek V4 Pro).
They are interchangeable behind `code-channel`; the lead agent writes TZ and accepts results only.
Owner 16.10: daily SDK spend cap 3 USD for all agents together; per-run ceiling 2 USD stays.
Code of both units is written by the Claude SDK through `sdk-agent code` (owner priority SDK). Code index: repowise/CBM checked, not needed (tool files read whole by the wrapper).

## U1 — bin/sdk-agent, bin/sdk-agent-test
1. Every appended runs-log line gets a numeric field `ts` (epoch seconds of the append).
2. `RUNS_LOG` may be overridden by env `SDK_AGENT_RUNS_LOG` (tests only); default stays `/root/workspaces/tools/sdk-agent/runs.jsonl`.
3. Constant `DAILY_CAP=3.00`. Before loading the key and before any network call, sum `total_cost_usd` of log lines whose `ts` >= today's local midnight (missing log = 0; lines without `ts` are ignored). If spent + requested budget > DAILY_CAP: print `sdk-agent: refused: daily cap 3.00 USD (spent X today)` to stderr, exit 6.
4. TZ file list: besides `FILE: <path>` lines, accept one line starting `Files:` whose paths are in backticks (same rule as code-channel: split on backtick, take every second piece). Union, 1..5 paths, same path guard.
5. New mode `read [--budget USD] [--effort E] WORKTREE TZ_FILE`: same worktree checks as `code`; runs the engine inside WORKTREE with tools `Read,Grep,Glob` only (`--tools Read,Grep,Glob --allowedTools "Read Grep Glob" --permission-mode dontAsk --restricted --add-dir WORKTREE`), no JSON schema; prints the model's text answer to stdout; never writes files. Usage text lists the mode.
6. Tests (offline, no key, no network): daily cap refusal rc 6 with a fake log of today's lines; `Files:` line parsed (refusal of an outside path given only in a `Files:` line, rc 2); `read` without args rc 2; existing checks stay.

## U2 — bin/code-channel, bin/code-channel-test, config/code-channel.json
1. Ladder entry id `sdk` (`{"id":"sdk","enabled":true,"model":"claude-haiku-5-5"}`), placed first in config. `go` model, resume_model, audit_model -> `opencode-go/deepseek-v4-pro`; alt_models -> `opencode-go/glm-5.3-flash`, `opencode-go/deepseek-v4.1-flash`.
2. `sdk_agent=${CODE_CHANNEL_SDK_AGENT:-"$root/bin/sdk-agent"}` (env override for tests). Absolute TZ path computed before `cd`.
3. Function `run_sdk`: code mode runs `"$sdk_agent" code "$PWD" "$tz_abs"`, audit mode runs `"$sdk_agent" read "$PWD" "$tz_abs"`, with `CODE_CHANNEL_ACTIVE=1`; prints `code-channel: mode=<mode> form=sdk rc=<rc>` to stderr; returns 0 on success, 17 on any failure (17 is not in the stop list, so the ladder switches to the next form).
4. Ladder loop: `sdk` uses `run_sdk`, other ids keep `run_form`; change detection, audit tree check and switch message unchanged. Direct form `code-channel sdk <project> <tz>` runs `run_sdk`; `--model` with `sdk` exits 3.
5. Tests with a fake sdk-agent via `CODE_CHANNEL_SDK_AGENT`: sdk success with a file change -> rc 0 and opencode not called; sdk rc 6 -> switch sdk→go and opencode called; audit mode calls `sdk-agent read`. Final PASS count updated.

Files: `bin/sdk-agent` `bin/sdk-agent-test` `bin/code-channel` `bin/code-channel-test` `config/code-channel.json` `docs/code-channel.md` `docs/tz/2026-10-16-dcfg-khdsp-two-hands.md`
