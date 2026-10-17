# TZ dcfg-wvjfr — status line v3 (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Reconnaissance: read only `hooks/statusline-command.sh` (current v2, commit f8305cd). Keep its input handling, colors, `?`/`null` safety and the SDK sum; change only the layout below.

## U1
Owner feedback on v2: limits must be indicator bars like the context bar; labels must be understandable; the reset time must not merge with the percent; show the project folder name. Do not add task status or session name.

Output — exactly 3 lines, segments joined by `  ·  ` (two spaces, middle dot, two spaces). Any segment whose data is absent is skipped (never `?`/`null`); a line with no segments is not printed.

Line 1: `<model> · <effort> · 📁 <project> · ⎇ <branch> · +<added>/-<removed>`
- project: last path component of `workspace.project_dir` (else of `cwd`). If `workspace.current_dir` differs from `workspace.project_dir` and lies inside it, append ` › <relative subpath>` (e.g. `📁 projects › clients/agramak`).
- effort, branch, lines: as in v2.

Line 2: `контекст <bar> <n>%  ·  кэш <n>%  ·  сессия $<x.xx>`

Line 3: `лимит 5ч <bar> <n>% (сброс в HH:MM)  ·  неделя <bar> <n>% (сброс DD.MM в HH:MM)  ·  SDK за день <bar> $<x.xx> из $3.00`
- 5ч: `rate_limits.five_hour.used_percentage`, `resets_at`; неделя: `rate_limits.seven_day.*`; SDK: today's sum as in v2, percent = sum / 3.00 × 100.

Bar (same function for all four): 10 cells, filled `▓` = round(n/10), empty `░`; the whole bar and its number colored green < 50, yellow 50–79, red ≥ 80; reset color after the number.

Constraints: bash + jq + date + git only; ≤ 3 jq calls; no network, no writes; fast. Keep `#!/bin/bash` line 1.

## Acceptance (Claude runs after the edit)
1) full sample JSON → 3 lines; line 1 has `📁 projects`; line 2 starts `контекст ▓`; line 3 has `лимит 5ч ▓`, `(сброс в `, `неделя `, `SDK за день `, ` из $3.00`
2) `{}` → rc 0, no `?` and no `null`
3) `bash -n hooks/statusline-command.sh` → rc 0

Prohibitions: only the file above; no other files; no deletion; no secrets; no network.
