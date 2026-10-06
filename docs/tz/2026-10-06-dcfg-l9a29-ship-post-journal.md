# ТЗ dcfg-l9a29 — ship-post --watch не падает на stderr bd; пропуски с причиной

разведка — repowise (индекс: repowise/CBM проверен для tools; нет — `tools/bin/code-memory-enable`), затем `grep -n`.
Принципы: KISS, YAGNI, fail fast, least astonishment. Не трогать ничего вне двух файлов ниже.

## U1 — поток событий: строка не-JSON не роняет watch
Файл: `bin/ship-post`, функция `do_watch`.
Факт: `:440` запускает `bd events tail --since "$seq" --follow --json 2>&1`. bd на каждой записи печатает в stderr
`beads: auto-export warning: no Dolt remote configured.` (и ещё 2 строки `beads: …`). Строка попадает в поток,
`:456` `jq -er '.seq …'` падает (`jq: parse error: Invalid numeric literal at line 1, column 7`) → `die 'malformed journal record'`
→ pm2 рестарт (18 рестартов за сутки, `/root/.pm2/logs/ship-post-error.log`).
Правка: сразу после `ev="$partial$ev"; partial=''` (`:449`) — строка, не начинающаяся с `{`, печатается в stderr как
`ship-post: bd: <строка>` и цикл идёт дальше (`continue`). `2>&1` не убирать: JSON-ошибка `events_journal_truncated` (`:450`)
может прийти по stderr. JSON-строка без валидного `.seq` по-прежнему `die 'malformed journal record'` (fail fast сохраняется).

## U2 — пропуск закрытого атома пишется с причиной
Файл: `bin/ship-post`, функция `scan_repo`.
Факт: `:340` (нет assignee), `:342` (ветка не `<owner>/<atom>[-*]`), `:343` (Agent ≠ assignee), `:372` (ТЗ не файл внутри worktree)
делают `skip` молча. Коммиты с трейлером `Atom:` у закрытого атома не доставляются, и в логе нет ни слова.
Правка: в этих четырёх местах, если атом закрыт (`jq -r '.[0].status' <<<"$st"` == closed), печатать в stdout
`skip <atom> <причина>` (причины: `no assignee`, `branch <branch> != <owner>/<atom>`, `agent mismatch`, `tz not a file in worktree`).
Незакрытый атом — молча, как сейчас. Строки `:334`, `:336` не менять. Счётчики `ok/failed/skip` не менять.

## U3 — проверки
Файл: `bin/ship-post-test` (свой harness: `fail()`, итог `checks=N failures=M`).
Добавить 2 проверки по образцу существующих:
1) поток событий с не-JSON строкой `beads: auto-export warning` перед валидной записью: watch не завершился с
   `malformed journal record`, в stderr есть `ship-post: bd: beads: auto-export warning`.
2) закрытый атом с трейлером `Atom:` на ветке, не совпадающей с `<owner>/<atom>`: в stdout `skip <atom> branch`.
Тест: `bin/ship-post-test` один прогон → `failures=0`.

Критерии:
1) `grep -n "ship-post: bd: " bin/ship-post` → ≥1 строка в `do_watch`
2) `grep -c "skip \$atom" bin/ship-post` → ≥5 (было 1 — dirty)
3) `bin/ship-post-test` → `failures=0`

Паспорт источников: только код этого репо (`bin/ship-post:319-377`, `:400-466`), лог `/root/.pm2/logs/ship-post-error.log`
(строки 2026-10-06T22:34:25). Внешних API нет.
