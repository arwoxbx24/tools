# TZ dcfg-uo1hg v2 — test 22 follows the live ladder (codex rung off)

Done (do not touch): `config/code-channel.json` codex rung `"enabled": false` (owner 12.10: code only via OpenCode Go). CI PR #246 failed only on check 22: `FAIL 22: rc=0 out=go opencode-go/glm-5.3-flash - audit=opencode-go/longcat-2.5-preview-free` — the check still expects a second line `codex - high`.

## U1

File: `bin/code-channel-test` only. разведка — repowise.

1. Line with `check 22`: change the expected `--plan` output from `go opencode-go/glm-5.3-flash - audit=opencode-go/longcat-2.5-preview-free\ncodex - high` to exactly `go opencode-go/glm-5.3-flash - audit=opencode-go/longcat-2.5-preview-free` (drop the `\ncodex - high` part, keep the quoting style). Change nothing else.

Rules: no other files, no model test runs, do not commit.

Done check:
1. `grep -c "codex - high" bin/code-channel-test` → `0`
2. `bash bin/code-channel-test` → all PASS, rc 0
