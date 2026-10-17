# TZ dcfg-hnqxk.2 (v3 of dcfg-hnqxk) — receipt fixtures and final PASS line

ТЗ v3 — причина: goal AC1 requires the last line of bin/tmux-send-test to be exactly `PASS`; goal AC2 requires a fixture proving rc 0 comes only after the message id appears in the receiver log. Today the test ends with `PASS 20/20` and has no such fixture.
разведка — repowise (`repowise context bin/tmux-send bin/tmux-send-test`).

FILE: bin/tmux-send-test
Check: bin/tmux-send --help

## U1 — two receipt fixtures (bin/tmux-send-test)
Use the existing fake TUI stub and `TMUX_SEND_RECEIPT_LOG`, same style as the matrix cells:
- `receipt-late`: the stub appends the submitted line (with its `[ts:` id) to the log only 2 seconds after submit. Expect rc 0, stdout contains `delivered id=` and `receipt=`, and the measured elapsed time of the tmux-send call is >= 2 seconds. Print `PASS receipt-late` or `FAIL receipt-late`.
- `receipt-wrong-id`: the stub appends the submitted text to the log but with a different id (replace `[ts:<id>]` by `[ts:ts-0-0]`). Expect rc 1 and stderr contains `no receipt`. Print `PASS receipt-wrong-id` or `FAIL receipt-wrong-id`.
Use `TMUX_SEND_RECEIPT_WAIT=5` for both.

## U2 — summary lines (bin/tmux-send-test)
- Replace the current final line `PASS <passed>/<total>` with `total=<passed>/<total>`.
- After it print exactly one more line: `PASS` when every check passed, else `FAIL`; exit 0 on PASS, 1 on FAIL.
- Keep every existing check and the `matrix=<n>/<n>` line unchanged.

Rules: least code; bash only; no other files; forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `~/.codex/*.toml`, `auth.json`, `rm`, push, global installs.
