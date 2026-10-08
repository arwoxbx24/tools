# dcfg-zc2wc — layer 1

## U1
Owner R019: layer1 only; budget/top-up require Vercel login.
Architecture: one Bash executable for Claude/Codex, two exact free IDs and UTC expiry before key/network, fixed endpoints, sanitized request, cost0 required. No fallback/retry. Key stays in registered secrets file; no value printed.
Scope: bin/vercel-free, scripts/tests/vercel-free-selfcheck.sh, this TZ; replace Codex recipe manual key read with executable call. Total changed lines <=100.
Acceptance: bash scripts/tests/vercel-free-selfcheck.sh -> PASS paid_id_rc=64 network_calls=0. Grep key name by filenames only. No real model request.
Delivery: ship-post layer1, then keep existing atom in_progress with login control point by explicit owner order. No full acceptance claim.
Rollback: restore prior Codex recipe block and revert scoped tool delivery.
Sources: https://vercel.com/docs/ai-gateway/sdks-and-apis/openai-chat-completions ; https://vercel.com/docs/ai-gateway/modalities/evaluation#http-api
Expiry: Ling20261014, Laya20261101 UTC, as documented in existing shared recipe and linked official promotion announcements.
