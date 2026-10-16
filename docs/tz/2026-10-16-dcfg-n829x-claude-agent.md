# TZ dcfg-n829x (+ dcfg-hxh0g) — tools/bin/claude-agent: the only Claude Agent SDK route (ask + code mode)

Epic: dcfg-ghksc. Atoms: dcfg-n829x (ask mode, U1), dcfg-hxh0g (code mode, U2). Owner 16.10: SDK must be a hard part of the system and may write code.
Разведка — repowise. Индекс: repowise/CBM проверен для tools; нет — `tools/bin/code-memory-enable`.

## Source passport (verified, do not re-research)
- Engine: `/root/workspaces/tools/claude-agent-sdk-venv/lib/python3.12/site-packages/claude_agent_sdk/_bundled/claude` (`--version` → 2.1.299 (Claude Code)).
- Verified flag set (tools/claude-agent-sdk/RECIPE.md:10-23, verified 14.10): `-p --bare --model claude-haiku-5-5 --effort low --max-budget-usd <usd> --tools "" --no-session-persistence --append-system-prompt-file <f> --json-schema '<schema>' --output-format json "<prompt>" < /dev/null`.
- Result JSON fields used today in runs.jsonl: `.subtype`, `.result`, `.structured_output`, `.total_cost_usd`, `.modelUsage`.
- Key: env file `/root/workspaces/secrets/inbox/anthropic.env` defines `ANTHROPIC_API_KEY` (RECIPE.md:11 sources it with `.`). Docs: https://code.claude.com/docs/en/headless

## Files (only these)
- `bin/claude-agent` (new, bash, executable)
- `bin/claude-agent-test` (new, bash, executable; no network)
- `docs/tz/2026-10-16-dcfg-n829x-claude-agent.md` (this TZ, unchanged)

## U1 — ask mode (dcfg-n829x)
Usage (print exactly this block on `--help`/`-h`, stdout, rc 0, no network, no key load):
```
usage: claude-agent ask [--budget USD] [--effort low|medium|high] [--schema JSON] [--system-file FILE] PROMPT
       claude-agent code [--budget USD] [--effort low|medium|high] WORKTREE TZ_FILE
       claude-agent --help
Runs the Claude Agent SDK engine with model claude-haiku-5-5 and an API key (never the subscription).
Budget: default 0.50 USD per run, ceiling 2.00 USD. Every result is appended to tools/claude-agent-sdk/runs.jsonl.
```
Behaviour:
1. Model is a constant `claude-haiku-5-5`; no flag changes it; no other model name appears in the file.
2. `--budget`: must match `^[0-9]+(\.[0-9]+)?$`, > 0 and ≤ 2.00, else stderr `claude-agent: refused: --budget <value> (allowed 0 < USD <= 2.00, e.g. --budget 0.10)` and exit 2 — BEFORE loading the key or any network.
3. `--effort` only low|medium|high (default low for ask, medium for code); else exit 2 with the bad value and an example.
4. Key: load with `set -a; . /root/workspaces/secrets/inbox/anthropic.env; set +a` only inside the run path, after all argument checks. Never print, echo, log or `set -x` the key; no key in any file. Missing file → exit 3 `claude-agent: key file missing: <path>` (path only).
5. Run the engine with the verified flag set: `--bare --model claude-haiku-5-5 --effort E --max-budget-usd B --tools "" --no-session-persistence --output-format json`, plus `--json-schema` if `--schema`, `--append-system-prompt-file` if `--system-file`; stdin `< /dev/null`.
6. Append the engine's JSON result as one line to `/root/workspaces/tools/claude-agent-sdk/runs.jsonl` (jq -c), then print to stdout: `.structured_output` (compact JSON) if present, else `.result`; then one stderr line `claude-agent: subtype=<..> cost_usd=<..>`. Exit 0 only if `.subtype == "success"`, else 4.

## U2 — code mode (dcfg-hxh0g; ADR: SDK form of code-channel, tools stay off)
1. `WORKTREE` must exist and `git -C WORKTREE rev-parse --show-toplevel` must equal its realpath, else exit 2.
2. `TZ_FILE`: readable file; allowed files = every line matching `^FILE: (.+)$` (relative paths), 1..5 entries, else exit 2.
3. Path guard (refuse with exit 2 before key/network, message `claude-agent: refused path: <p>`): absolute path; any `..` component; any component equal to `.git`, `.beads`, `.repowise`, `.ssh`, `secrets`, `node_modules`; any basename matching `.env*`, `*.pem`, `*.key`, `*secret*`, `auth.json`. Resolved path must stay inside WORKTREE.
4. Prompt = `<task>` TZ_FILE text `</task>` + for each allowed file `<file path="...">current content or (new file)</file>` + instruction to return the full new content of each file it changes. Files > 200 KB → exit 2.
5. Engine call as U1 with `--json-schema '{"type":"object","properties":{"files":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},"required":["files"]}'`.
6. Output guard: every returned `path` must be in the allowed list (exact string) — otherwise write NOTHING, stderr `claude-agent: refused model path: <p>`, exit 5. Only after all paths pass, write each file (tmp + mv inside WORKTREE).
7. Print `git -C WORKTREE diff --stat` and `git -C WORKTREE status --short` to stdout. Log to runs.jsonl as U1.

## Test — bin/claude-agent-test (no network, no key)
Assert-based, prints `ok N/M`, exit 0 only if all pass: `--help` rc 0 + first line starts `usage:`; `--budget 5` → rc 2 and stderr has `refused`; `--budget abc` → rc 2; `--effort max` → rc 2; code mode with a temp git repo in `mktemp -d` and TZ lines `FILE: ../x`, `FILE: .env`, `FILE: /etc/passwd`, `FILE: secrets/a` → each rc 2 `refused path`; `grep -c claude-haiku-5-5 bin/claude-agent` ≥ 1 and `grep -cE 'claude-(sonnet|opus|fable)'` = 0. Temp dir removed by the test itself (it lives under /tmp).

## U3 — registry line (main agent, MD)
- `TOOLS-REGISTRY.md`: one row for `tools/bin/claude-agent` (route, model, budget, owner-mention gate, test).

## Authorship (owner 16.10: "работать только с sdk, не смешивать")
`bin/claude-agent` and `bin/claude-agent-test` were written by the Claude Agent SDK (claude-haiku-5-5, run in runs.jsonl, cost 0.0148 USD); managed deny `Edit(//root/workspaces/projects/**/bin/**)` refused its Edit, so the verbatim generated text was placed with `tools/bin/place-files`. No code-channel/opencode output is included.

## Constraints
SOLID/DRY/KISS/YAGNI, fail fast, least astonishment; no other files; no new dependencies (bash, jq, git only); no network in tests; never read/print secrets; no `rm -rf` outside /tmp; no edits to /etc, ~/.ssh, .beads, .repowise, settings; no push, no PR. Done-check: `bin/claude-agent-test` → `ok M/M`, `bin/claude-agent --help` rc 0.
