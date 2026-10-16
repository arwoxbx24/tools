# TZ dcfg-sktr5 — rename SDK wrapper claude-agent -> sdk-agent (owner 16.10: "пусть будет sdk-agent пока так")

## U1 — code (written by the Claude Agent SDK through the wrapper's code mode)
In both files replace the tool name `sdk-run` with `sdk-agent` everywhere: header comments, usage text, `die`/`printf` message prefixes (`sdk-agent: ...`), test variable path (`$here/sdk-agent`), temp dir name (`/tmp/sdk-agent-test.XXXXXX`), test header (`sdk-agent-test — offline assertions for bin/sdk-agent`).
Header line 3 of bin/sdk-agent becomes `# TZ: docs/tz/2026-10-16-dcfg-sktr5-sdk-agent.md`.
`RUNS_LOG` becomes `/root/workspaces/tools/sdk-agent/runs.jsonl`; usage line "Every result is appended to tools/sdk-agent/runs.jsonl."
Add one usage line after "Runs the Claude Agent SDK engine ...": "sdk-agent is a paid API program, not a Claude Code agent or subagent."
Keep `ENGINE` path exactly as is (vendor package path). Keep the mode-preserving write (`chmod --reference`). Change nothing else: logic, flags, model, budgets, guards stay identical.
FILE: bin/sdk-agent
FILE: bin/sdk-agent-test

## U2 — registry (main agent, MD)
TOOLS-REGISTRY.md row: `tools/bin/sdk-agent`, test `bin/sdk-agent-test`, log `sdk-agent/runs.jsonl`, note "not a Claude Code agent/subagent".

## U3 — defect fixed 16.10 (already in code): code mode kept 0600 from mktemp; now copies the target's mode.
