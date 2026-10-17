# TZ dcfg-dfz0g — status line: short English labels (owner 17.10)

FILE: hooks/statusline-command.sh

Executor: sdk-agent code. Read only `hooks/statusline-command.sh`. Change only the label strings below; layout, bars, colors, logic stay as they are.

## U1
Exact replacements (line numbers as of commit 2bd2a9a):
- line 47 date format `'+%d.%m в %H:%M'` → `'+%d.%m %H:%M'`
- line 80 `контекст ` → `context `
- line 84 `кэш ` → `cache `
- line 87 `сессия ` → `session `
- line 94 `лимит 5ч ` → `5h `
- line 95 ` (сброс в $t)` → ` (reset $t)`
- line 100 `неделя ` → `week `
- line 101 ` (сброс $t)` → ` (reset $t)`
- line 113 `SDK за день ` → `SDK today `, and `) из \$3.00` → `) / \$3.00`

Target output example:
```
context ▓▓▓░░░░░░░ 26%  ·  cache 98%  ·  session $15.14
5h ░░░░░░░░░░ 3% (reset 14:10)  ·  week ▓░░░░░░░░░ 12% (reset 21.10 18:00)  ·  SDK today ░░░░░░░░░░ $0.08 / $3.00
```

## Acceptance (Claude runs after the edit)
1) no Cyrillic left: `grep -cP '[\x{0400}-\x{04FF}]' hooks/statusline-command.sh` → `0`
2) full sample → 3 lines with `context `, `cache `, `session $`, `5h `, `(reset `, `week `, `SDK today `, ` / $3.00`
3) `{}` → rc 0, no `?`/`null`; `bash -n` → rc 0

Prohibitions: only the file above; no other changes.
