# TZ dcfg-bthgb.1 v2 U2 — drop --bare, keep API-key-only by isolation

Why: real run proved `--bare` hides WebSearch, WebFetch, Agent, Skill. Doc code.claude.com/docs/en/env-vars, CLAUDE_CODE_SIMPLE (= --bare): "only the Bash, file read, and file edit tools … Disables auto-discovery of hooks, skills, custom commands, subagents". Doc code.claude.com/docs/en/authentication: "In non-interactive mode (-p), the key is always used when present"; subscription OAuth credentials rank last and are read from the config dir (`CLAUDE_CONFIG_DIR` → `.credentials.json`). Doc env-vars: `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` "Set to `1` to force one model onto subagents".

## U2 — bin/sdk-agent
Skills: caveman:surgical-patch (one function), security-review (auth boundary: API key only, never the subscription)
1. Add `readonly ENGINE_HOME="/root/workspaces/tools/sdk-agent/engine-home"` next to the other readonly paths.
2. `run_engine`: remove `--bare` from `args` (line ~139). Keep everything else.
3. In the engine subshell (the line that sources the key file and runs `"$ENGINE"`): before sourcing, `mkdir -p -- "$ENGINE_HOME"` (die rc 6 if it fails, outside the subshell is fine); run the engine through `env -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY -u ANTHROPIC_PROFILE CLAUDE_CONFIG_DIR="$ENGINE_HOME" CLAUDE_CODE_SUBAGENT_MODEL="$MODEL" CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 "$ENGINE" "${args[@]}" "$prompt"` (the key variables sourced from KEY_FILE stay exported for the engine only, as now).
4. Before running the engine, refuse with rc 6 `sdk-agent: refused: credentials found in $ENGINE_HOME` if `$ENGINE_HOME/.credentials.json` exists (fail closed: the subscription must never be reachable).
5. Update the usage text line "Runs the Claude Agent SDK engine with model claude-haiku-5-5 and an API key (never the subscription)." — keep it; add "Engine config dir: tools/sdk-agent/engine-home (no login stored there)."
Do not add Bash, Edit, Write, NotebookEdit or --fallback-model.

Files: `bin/sdk-agent`
