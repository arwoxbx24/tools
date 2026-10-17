# TZ dcfg-hnqxk.1 v2 — run the matrix inside the channel and fix until it passes

ТЗ v2 — причина: the owner requires one tool only (code-channel); the test must run inside the channel, not by the lead.
разведка — repowise (`repowise context bin/tmux-send bin/tmux-send-test`).

FILE: bin/tmux-send
Check: bin/tmux-send-test

## U1
Read the current bin/tmux-send and bin/tmux-send-test (the edits from TZ docs/tz/2026-10-17-dcfg-hnqxk.1-receipt.md are already applied). The channel runs bin/tmux-send-test after your edits.
If bin/tmux-send would make any check of bin/tmux-send-test fail, return the exact edits to bin/tmux-send that fix it. If nothing needs fixing, return no edits.
Rules: least code; bash only; no other files; forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `~/.codex/*.toml`, `auth.json`, `rm`, push, global installs.
