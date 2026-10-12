# TZ dcfg-uo1hg — code channel: OpenCode Go only, codex rung off

## U1

Owner 12.10: Codex quota is exhausted; code must be written only by the paid OpenCode Go subscription. Evidence: `runs.jsonl` has 14 `form=codex` runs, the last 3 today.

Change: `config/code-channel.json` ladder entry `codex` → `"enabled": false`. Failures of the go rung are handled by session continuation (dcfg-j83xb v2), not by falling back to Codex.

Done check: `jq '.ladder[]|select(.id=="codex")|.enabled' config/code-channel.json` → `false`.
