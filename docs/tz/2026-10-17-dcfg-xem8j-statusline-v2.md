# TZ dcfg-xem8j — status line v2 (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Reconnaissance: read only `hooks/statusline-command.sh` (2 lines today). Rewrite it completely (old = whole current content).

## U1
Input: Claude Code passes session JSON on stdin (code.claude.com/docs/en/statusline). Fields used (any may be absent — then skip that segment, never print `?` or `null`):
`model.display_name`, `effort.level`, `thinking.enabled`, `workspace.project_dir`, `cwd`, `worktree.branch`, `cost.total_cost_usd`, `cost.total_lines_added`, `cost.total_lines_removed`, `context_window.used_percentage`, `rate_limits.five_hour.used_percentage`, `rate_limits.five_hour.resets_at` (Unix epoch seconds), `rate_limits.seven_day.used_percentage`, `rate_limits.seven_day.resets_at`, `prompt_cache.hit_ratio` (0..1), `prompt_cache.warm` (bool).

Output — exactly 2 lines, segments joined by ` · `:
Line 1: `<model> · <effort> · <dir> · ⎇ <branch> · +<added>/-<removed>`
- effort: `effort.level`; if absent and `thinking.enabled == true` → `thinking`; else skip.
- dir: `workspace.project_dir`, else `cwd`; leading `$HOME` → `~`.
- branch: `worktree.branch`; else `git -C <dir> branch --show-current 2>/dev/null`; empty → skip.
- lines: only if both counts present and their sum > 0.

Line 2: `ctx <bar> <n>% · 5ч <n>% ↻<HH:MM> · нед <n>% ↻<DD.MM HH:MM> · кэш <n>% <warm|cold> · сессия $<x.xx> · SDK сегодня $<x.xx>/$3.00`
- bar: 10 cells, `▓` filled = round(n/10), `░` the rest.
- reset times: local time from the epoch; 5ч `HH:MM`, нед `DD.MM HH:MM`.
- SDK сегодня: sum of `total_cost_usd` in `/root/workspaces/tools/sdk-agent/runs.jsonl` with `ts` ≥ today's local midnight; 2 decimals; file missing → skip.
- Colors: green < 50 %, yellow 50–79 %, red ≥ 80 % on ctx, 5ч, нед, SDK (share of 3.00).

Constraints: bash + jq + date + git only; ≤ 3 jq calls; no network, no writes; fast.

## Acceptance
1) full sample JSON → 2 lines with model, effort, `~/`, `ctx`, `5ч`, `нед`, `сессия $`, `SDK сегодня $…/$3.00`
2) `{}` → rc 0, no `?` and no `null`
3) `bash -n hooks/statusline-command.sh` → rc 0
