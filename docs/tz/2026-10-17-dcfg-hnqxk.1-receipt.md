# TZ dcfg-hnqxk.1 — tmux-send: delivered = receipt in the receiver's session log

Owner 17.10: "100% подтверждение с двух сторон". Epic dcfg-hnqxk (also closes dcfg-bt0e0).
Fact 17.10: two sends to a Claude window with an active /goal returned rc 1 (`expect 'Working|esc to interrupt|\([0-9]+s ·' not matched`), yet both texts are in the receiver transcript (one as `type:user`, one as `queue-operation enqueue` + `queued_command`). The screen regex is not proof in either direction.
Reconnaissance: repowise (`repowise context bin/tmux-send`, indexed_commit = HEAD); CBM does not index these extensionless scripts.

FILE: bin/tmux-send
FILE: bin/tmux-send-test

## U1 — message id (bin/tmux-send)
Each send gets an id `ts-<epoch seconds>-<pid>`; the text sent is `<text> [ts:<id>]`.

## U2 — receiver log (bin/tmux-send)
Resolve the receiver's own session log for the target pane:
1. `TMUX_SEND_RECEIPT_LOG` set → that file (tests).
2. Else take `#{pane_pid}` of the target and its descendants down to depth 2 (`ps -o pid= --ppid`).
   - Claude: the first pid with `$HOME/.claude/sessions/<pid>.json` → `jq -r .sessionId` → the first `find "$HOME/.claude/projects" -maxdepth 2 -name "<sessionId>.jsonl"`. Real chain seen 17.10: pane_pid 2539744 → child 3000013 → sessions/3000013.json → projects/-root-workspaces-tools-bin/<sid>.jsonl.
   - Codex: the first pid whose `/proc/<pid>/fd/*` links to a path matching `*/.codex/sessions/*rollout-*.jsonl` → that path.
   - Only `grep -F` of the id is run on that file. Its content is never printed.
3. No claude/codex process in the pane → no receipt: keep today's screen rule and `--expect` unchanged, and print `receipt=none`.
4. A claude/codex process is found but no log resolves → rc 1, stderr `tmux-send: no receipt log for <target>`.

## U3 — delivery decision (bin/tmux-send)
- After pasting the text, press Enter as today. If the pane shows `tab to queue message` (busy Codex), press Tab instead of Enter.
- Then check `grep -qF "[ts:<id>]" <log>` once per second for up to `TMUX_SEND_RECEIPT_WAIT` seconds (default 30). This is the wrapper's hang ceiling, not an agent wait.
- Enter (or Tab) is re-pressed only while the text is still visible in the input field and no receipt exists, at most 3 times as today. Never press a key after the receipt is found.
- Receipt found → rc 0, stdout `delivered id=<id> receipt=<log>:<line number>`.
- Not found → rc 1, stderr `tmux-send: no receipt id=<id> in <log> after <N>s`.
- When a receipt log exists, the screen regex and `--expect` no longer decide rc.
- `--help` stays one usage line on stdout, rc 0, no action; it must contain the word `receipt` and the env names `TMUX_SEND_RECEIPT_LOG` and `TMUX_SEND_RECEIPT_WAIT`.

## U4 — test matrix (bin/tmux-send-test)
Keep every existing check. Add a matrix on the isolated test tmux server, using the existing fake TUI stub; extend the stub so that, on submit (Enter or Tab), it appends the submitted line to a log file given as an extra argument:
- Claude window (`❯`) and Codex window (`›`), each in states: idle, Working, active /goal (footer `◎ /goal active (5m)`, no Working text — the 17.10 case), fresh start. Every cell: rc 0 and the `[ts:` id is in the log.
- Busy Codex showing `tab to queue message`: Tab queues it → rc 0 and id in log (dcfg-bt0e0).
- Lost message: the stub swallows the text (writes nothing to the log) → rc 1 and stderr contains `no receipt`.
- Use `TMUX_SEND_RECEIPT_WAIT=3` in the test.
- Print `matrix=<passed>/<total>` before the final line; the final line stays `PASS` only when every check passes.

Rules: least code; bash only, no new dependencies; no other files change; principles SOLID/DRY/KISS/YAGNI; forbidden: secrets, `.env`, keys, `~/.ssh`, `/etc`, `~/.codex/*.toml`, `auth.json`, `rm`, push, global installs.
