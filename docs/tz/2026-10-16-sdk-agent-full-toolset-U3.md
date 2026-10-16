# TZ dcfg-bthgb.1 v3 U3 — haiku only, no web in code mode, restricted everywhere

Why (owner 16.10: "только модель Хайку 5.5"): real read run used claude-sonnet-5-5 (0.0548824 USD) for its subagent. Cause: /etc/claude-code/managed-settings.json env `CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5-5` wins over our process env. Security: code mode must not mix project code, untrusted web pages and outbound fetch (an injected page could plant code). Ask mode without --bare would read project settings and hooks of the current directory.

## U3 — bin/sdk-agent
Skills: caveman:surgical-patch (one file), security-review (model pin, network boundary)
1. Replace `readonly TOOLS=…` with two lines: `readonly TOOLS_CODE="Read,Grep,Glob,Skill"` and `readonly TOOLS_READ="Read,Grep,Glob,Skill,WebSearch,WebFetch"`. `cmd_code` passes `"$TOOLS_CODE"`, `cmd_read` passes `"$TOOLS_READ"`. No Agent tool anywhere.
2. In the engine call remove `CLAUDE_CODE_SUBAGENT_MODEL="$MODEL" CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`.
3. `run_engine`: put `--restricted --strict-mcp-config` into the base `args` for every mode (ask included); the tools branch keeps `--tools … --allowedTools … --permission-mode dontAsk --add-dir "$workdir" --mcp-config "$MCP_CONFIG"` (no second `--restricted`/`--strict-mcp-config`).
4. Model pin guard: right after the trimmed result is appended to runs.jsonl, if `jq -e '(.modelUsage // {}) | keys | all(. == "claude-haiku-5-5")'` (use `$MODEL`) fails on `$RESULT`, die rc 4 with `refused: model outside pin: <comma-separated keys>`. Also add `models` (the modelUsage keys array) to the trimmed record appended to runs.jsonl.
5. Prompts: code — "You may use Read, Grep, Glob, Skill and the repowise MCP tools."; read — "you may use Read, Grep, Glob, Skill, WebSearch, WebFetch and the repowise MCP tools.".
Do not add Bash, Edit, Write, NotebookEdit, Agent or --fallback-model.

Files: `bin/sdk-agent`
