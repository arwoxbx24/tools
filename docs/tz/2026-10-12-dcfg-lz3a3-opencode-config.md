# TZ dcfg-lz3a3 — code-channel: pass the OpenCode channel config via OPENCODE_CONFIG

## U1

Architecture (ADR v3, bd dcfg-x171s.12): no timers in our code. Stall detection is OpenCode's own: `config/opencode-channel.json` sets `provider.opencode-go.options.timeout=false` (removes the 300000 ms total-request cap; chunkTimeout/headerTimeout stay at OpenCode defaults and abort only a silent stream). Retries are capped inside OpenCode 1.18.30 (`RETRY_MAX_RETRIES = 5`).

Sources:
- https://opencode.ai/docs/config/ — "Specify a custom config file path using the `OPENCODE_CONFIG` environment variable."
- https://opencode.ai/docs/config/ — "`timeout` - Request timeout in milliseconds (default: 300000). Set to `false` to disable."

Already done (do not touch): `config/opencode-channel.json` exists; `config/code-channel.json` has top-level key `"opencode_config": "config/opencode-channel.json"` (path relative to the tools repo root).

Files: `bin/code-channel`, `bin/code-channel-test` only.

1. `bin/code-channel`: read `.opencode_config` from the channel config with jq the same way the script already reads other config fields. If the key is present, resolve it against the tools repo root (the directory the script already uses to find `config/`) and export `OPENCODE_CONFIG=<absolute path>` for the `opencode run` calls. If the key is set but the file does not exist — fail fast with the script's existing `fail` helper and exit 3. If the key is absent — do not export (fixtures without the key keep working). No new numeric constants, no timers.
2. `bin/code-channel-test`: add one check: with a fixture config that has `opencode_config` pointing to an existing file, the opencode stub sees `OPENCODE_CONFIG` equal to that absolute path. Use the existing stub/log mechanism; do not change other checks.

Rules: no other files, no model test runs, do not commit. Index: repowise/CBM checked; разведка — repowise.

Done check:
1. `grep -c OPENCODE_CONFIG bin/code-channel` → ≥ 1
2. `grep -cE "timeout [0-9]" bin/code-channel` → `0`
3. `bash -n bin/code-channel` → rc 0
4. `bash bin/code-channel-test` → all PASS, rc 0 (the one test run of this atom)
