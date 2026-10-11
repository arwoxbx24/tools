# TZ dcfg-0r2om + dcfg-bdvea — tmux-send: truthful delivery check on Claude Code and Codex TUIs

## U1 — verify submission in history, never in the input box; wait for paste before Enter

разведка — repowise (then `grep -n`, then Read of the edited file only).
Principles: SOLID, DRY, KISS, YAGNI. Smallest diff that fully works; no new options, no helpers for one-off use.

Files owned (change only these): `bin/tmux-send`, `bin/tmux-send-test`. This TZ file is read-only.

### Method: TDD, two runs
- Phase RED (done): cases 8-10 added to `bin/tmux-send-test`; on the old `bin/tmux-send` the run gave `FAIL 8: rc=1`, `FAIL 9: rc=0`, `FAIL 10: rc=1 dropped=1`, `PASS 7/10`.
- **CURRENT PHASE: GREEN** — in this run change ONLY `bin/tmux-send` per the Design. Do NOT modify `bin/tmux-send-test`. Target: `bash bin/tmux-send-test` → `PASS 10/10`, rc 0.

### Root cause (5 Whys)
rc 1 on a delivered message ← default expect `Working` is absent from the new Claude Code spinner ← success is inferred from one UI word instead of from the message itself ← no check that the text left the input box and reached history ← verification greps the whole pane, not regions. Fix the last two (region split + message-echo check), not just the default word.

### Defects (facts, bd dcfg-0r2om, dcfg-bdvea)
- A: current Claude Code spinner shows random verbs (`· Puttering… (10s · ↓ 533 tokens · thinking with medium effort)`, `Brewed for 37s`, `Thinking…`), not always `Working`. Default `expect=Working` (bin/tmux-send:9) gives rc 1 although the message may be submitted, or the real failure is hidden.
- B: `--expect` is grepped against the WHOLE pane (lines 57-66), including the input box, so text still sitting unsubmitted in the input box gives a false rc 0.
- C: fresh Codex window: `send-keys Enter` (line 53) is sent right after `send-keys -l` (line 52), before the TUI rendered the paste; the Enter is lost, text stays in the input box.

### Real pane layouts
- Claude Code: history lines; a submitted user message is echoed in history as a line starting with `❯ ` + text; while busy a spinner line (see A); then a rule line of `─` characters, the input line starting with `❯ ` (only `❯` when idle), another `─` rule, then a status bar.
- Codex: prompt marker `›`; busy line `Working (Ns • esc to interrupt)`.
- Plain shell / `cat` panes (existing tests 2-7): no rule line, no marker.

### Design (lead decision)
1. Split the captured pane (`capture-pane -p`, as today):
   - input region = from the last line made of `─` characters that lies above the last line starting with `❯` or `›`, to the end of the pane;
   - no such layout found (plain shell, `cat`) = input region is the last non-empty line;
   - history = all lines above the input region.
2. Message key = first 24 characters of the message with whitespace collapsed to single spaces (compare against the region text with whitespace collapsed the same way).
3. Before the first Enter: after `send-keys -l`, poll up to 5 times (sleep `$TMUX_SEND_SLEEP`-based step, default 1 s) until the key is visible in the input region; then send Enter. Not visible after the limit: send Enter anyway (keep current behaviour, the check below decides rc).
4. Success (rc 0) when EITHER `--expect` regex matches a line of HISTORY, OR the key appears in history AND the input region no longer contains the key. `--expect` is NEVER matched against the input region.
5. Default `--expect` regex: `Working|esc to interrupt|\([0-9]+s ·`. Update `--help` text with this default.
6. Keep: up to 3 Enter retries (sleep, capture, check, else Enter); `--help` contract (usage on stdout, rc 0, no tmux calls); rc meanings 0 = submitted, 1 = not submitted (`expect '<re>' not matched` on stderr), 2 = tmux error; target resolution code unchanged.

### Tests — extend `bin/tmux-send-test` (keep checks 1-7 unchanged, final line `PASS N/10`)
Private socket only (`TMUX_SEND_SOCKET`, server started with `-f /dev/null`, windows created with `-t t:`). Export `LC_ALL=C.UTF-8` so `❯`/`─` render. Fake TUI = a small bash script written by the test to its temp dir (no files outside temp), run in a new window: `stty -echo -icanon`, read one char at a time into a buffer, redraw the whole layout after each event (`clear`, history lines, `─────`, `❯ <buffer>`, `─────`, `status`). Modes by argument:
- `ok` (Claude-like): Enter moves the buffer into history as `❯ <buffer>` and adds the line `· Puttering… (3s · ↓ 10 tokens)`; input becomes empty.
- `stuck`: Enter is ignored, buffer stays in the input line.
- `slow`: each char is rendered only after 0.5 s without new chars (paste settling); an Enter that arrives before the buffered text is rendered is DROPPED and counted into a file `$tmp/dropped`; an Enter after render behaves like `ok`.
Cases:
- 8 (Defect A): mode `ok`, `tmux-send t:<win> 'hello claude spinner msg'` with default expect → rc 0.
- 9 (Defect B): mode `stuck`, `tmux-send t:<win> 'stuck-text-B9' --expect 'stuck-text-B9'` → rc 1 (expect matches only the input box).
- 10 (Defect C): mode `slow`, `tmux-send t:<win> 'slow paste message C10'` → rc 0, history contains `❯ slow paste message C10`, `$tmp/dropped` absent or 0.
Do not weaken or remove existing checks. If a case cannot pass, report the exact output instead of changing the case.

### Prohibitions
Only the two owned files. No `rm -rf` outside `/tmp`, no `--force`, no `reset --hard`, no real tmux server (`cl`) — tests use the private socket only. Do not commit.

### Acceptance
1. `bash -n bin/tmux-send` → rc 0.
2. `bash bin/tmux-send-test` → last line `PASS 10/10`, rc 0.
3. `bin/tmux-send --help` → rc 0, usage on stdout, shows the new default regex.
