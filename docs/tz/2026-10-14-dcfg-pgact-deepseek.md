# TZ dcfg-pgact — code-channel: allow DeepSeek models of OpenCode Go via --model

## U1
Goal: `bin/code-channel go <project> <tz> --model opencode-go/deepseek-v4.1-flash` passes the model check and runs that model. Default behavior without `--model` is unchanged.

Why: owner 14.10 ordered code through OpenCode Go DeepSeek. `bin/code-channel:111` accepts `--model` only when it equals `model`, `resume_model` or `audit_model` of the provider entry; two runs failed with `code-channel: модель не в конфиге: opencode-go/deepseek-v4.1-flash` (rc 3). `opencode models opencode-go` lists `opencode-go/deepseek-v4.1-flash` and `opencode-go/deepseek-v4-pro`.

Change:
1. `config/code-channel.json`, entry `"id": "go"`: add `"alt_models": ["opencode-go/deepseek-v4.1-flash", "opencode-go/deepseek-v4-pro"]`. Do not change `model`, `resume_model`, `audit_model`.
2. `bin/code-channel:9` schema check: also accept the optional field — `((.alt_models? // []) | type == "array" and all(.[]; type == "string"))`.
3. `bin/code-channel:110-113`: the override is valid when it equals `model`, `resume_model`, `audit_model`, or is listed in that entry's `alt_models`. Keep the same error text and rc 3 otherwise.
4. `docs/code-channel.md`: one line next to the `--model` line (line 9): `alt_models` in the provider entry lists extra models allowed for `--model`.
5. `bin/code-channel-test`: one case — an override listed in `alt_models` passes the model check; an override not listed still gives rc 3 `модель не в конфиге`. Follow how the existing cases stub providers (no network, no paid call).

Acceptance (from worktree root):
- `bin/code-channel-test` → all cases pass (its existing pass line), including the 2 new ones.
- `bash -n bin/code-channel` exit 0; `jq -e . config/code-channel.json` exit 0.
- `git diff --check` exit 0.

Rules: SOLID, DRY, KISS, YAGNI; minimal diff; разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`. No Anthropic/Claude models in this channel (platform split). No secrets. Do not commit; do not push.
Rollback: revert this commit.
