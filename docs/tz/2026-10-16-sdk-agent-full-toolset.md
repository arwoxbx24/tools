# TZ dcfg-bthgb.1 — sdk-agent: every engine capability the server policy permits

Why (owner 16.10): "SDK must perform all functions of a full toolset". Server policy (/etc/claude-code/managed-settings.json, allowManagedPermissionRulesOnly=true) allows WebSearch, WebFetch, Skill, Agent (except Explore, Plan), mcp__repowise; it denies Edit of code extensions and most Bash. Engine 2.1.299 `--help`: `--effort … (low, medium, high, xhigh, max)`; `--mcp-config <configs...>` "Load MCP servers from JSON files or strings"; `--strict-mcp-config` "Only use MCP servers from --mcp-config"; `--restricted` "removes … WebFetch unless --tools names it … (managed settings and --settings still apply; add --strict-mcp-config to skip MCP servers too)". Engine binary contains env `CLAUDE_CODE_SUBAGENT_MODEL`.
Index: repowise/CBM checked; one bash file + its test. Principles: KISS, YAGNI, fail fast, minimal diff; keep every existing guard (paths, Check, budget, daily cap, key only in engine subshell, exact edits).

## U1 — bin/sdk-agent, bin/sdk-agent-test
Skills: caveman:surgical-patch (2 files), ponytail:ponytail (minimal code), security-review (new tools at trust boundary)
1. `validate_effort` (line ~58): allow `low|medium|high|xhigh|max`; update the refusal text and the usage lines (`--effort low|medium|high|xhigh|max`).
2. Add `readonly TOOLS="Read,Grep,Glob,WebSearch,WebFetch,Agent,Skill"` near the other readonly values and `readonly MCP_CONFIG='{"mcpServers":{"repowise":{"type":"stdio","command":"/root/.local/bin/repowise","args":["mcp","--no-workspace"]}}}'`. `cmd_code` and `cmd_read` pass `"$TOOLS"` instead of `"Read,Grep,Glob"`.
3. `run_engine`, tools branch (line ~131): `--allowedTools` gets the tool names plus `mcp__repowise`; add `--mcp-config "$MCP_CONFIG" --strict-mcp-config`. Keep `--permission-mode dontAsk --restricted --add-dir "$workdir"`. In the engine subshell also set `CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"` so subagents stay on the pinned model.
4. New option `--json` for `ask` and `read` only (refuse for `code`, like `--schema`): print the whole engine result JSON (`$RESULT`) to stdout instead of the text. Add it to usage.
5. Prompts of `cmd_code` and `cmd_read`: replace "You may read any file of the repository with Read, Grep, Glob." with "You may use Read, Grep, Glob, WebSearch, WebFetch, the Agent tool for subagents, Skill and the repowise MCP tools."
6. Do NOT add Bash, Edit, Write, NotebookEdit or `--fallback-model`.
7. `bin/sdk-agent-test` (offline, no key): one case `--effort max` passes validation (e.g. `sdk-agent code --effort max` with a missing worktree fails on the worktree, not on effort); one case `--effort extreme` is refused; one case `code --json` is refused. Keep all other checks.

Files: `bin/sdk-agent` `bin/sdk-agent-test`
