# TZ dcfg-hnqxk.2 (v3 check) — run bin/tmux-send-test inside the channel

разведка — repowise (`repowise context bin/tmux-send bin/tmux-send-test`).

FILE: bin/tmux-send
Check: bin/tmux-send-test

## U1
bin/tmux-send-test now has fixtures `receipt-late` and `receipt-wrong-id` (TZ docs/tz/2026-10-17-dcfg-hnqxk-v3-fixtures.md). The channel runs bin/tmux-send-test after your edits.
If bin/tmux-send would make any check fail (rc 0 must come only after `grep -qF "[ts:<id>]"` finds the id in the receiver log; a different id must give rc 1 `no receipt`), return the exact edits to bin/tmux-send that fix it. If nothing needs fixing, return no edits.
Rules: least code; bash only; no other files; forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `~/.codex/*.toml`, `auth.json`, `rm`, push, global installs.
