# TZ dcfg-tfcy0 — status line: context bar against the auto-compact window (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Read only `hooks/statusline-command.sh` (lines 1-82 are enough). Minimal diff; layout, other segments, colors, `bar`, `paint` stay as they are. Principles: KISS, YAGNI.

## U1
1. In the jq field list (line 5-22) add one field `(.context_window.context_window_size | n)` at the end and a variable `ctx_win` at the end of the `read` on line 23.
2. Before `# line 2` compute the limit, one comment line `# shortcut: reads only user settings, not project settings or modelSettings; upgrade if those set a window`:
   - `limit=$CLAUDE_CODE_AUTO_COMPACT_WINDOW`; if empty: `limit=$(jq -r '.autoCompactWindow | numbers' "$HOME/.claude/settings.json" 2>/dev/null)`.
   - Keep `limit` only if it matches `^[0-9]+$`; if `ctx_win` is a whole number and `limit > ctx_win`, set `limit=ctx_win`.
3. Context segment (lines 78-81): `c=$(whole "$ctx_pct")`. If both `limit` and `ctx_win` are whole numbers > 0: `c=$(( (c * ctx_win + limit / 2) / limit ))` and suffix ` of $((limit / 1000))k`; else no suffix. Output: `context $(paint "$c" "$(bar "$c") $c%")$suffix`.

Example: used_percentage 26, context_window_size 1000000, autoCompactWindow 300000 → `context ▓▓▓▓▓▓▓▓▓░ 87% of 300k`.

## Acceptance (Claude runs after the edit)
1) sample above → line 2 contains `87%` and `of 300k`
2) `HOME=/nonexistent`, no env → percent equals used_percentage, no ` of `
3) `{}` → rc 0, no `?`/`null`; `bash -n` → rc 0

Prohibitions: only the file above; no other changes; no secrets, no network.
