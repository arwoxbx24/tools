# ТЗ dcfg-dt7rk — ship: ошибка gh видна, 5xx временный

разведка — repowise (индекс: repowise/CBM проверен для tools; нет — `tools/bin/code-memory-enable`), затем `grep -n`.
Принципы: KISS, fail fast, least astonishment. Править только `bin/ship`, функцию `gh_or70` (одна строка).

## U1
Факт: `bin/ship:164`
`gh_or70(){ local e; e=$("$@" 2>&1 >/dev/null) && return 0; grep -qiE 'HTTP 40[13]|authentication|could not connect|timeout' <<<"$e" && leave 70 gh; return 1; }`
— текст ошибки `gh` теряется (не печатается), 5xx GitHub (`HTTP 502`, `GraphQL: Something went wrong`) даёт `return 1`
→ `leave 50 merge` (`:167`). 06.10 PR 321 был CLEAN/MERGEABLE, курьер дважды получил 50 без причины в журнале.

Правка `gh_or70`:
1) при ошибке печатать `$e` в stderr одной строкой с префиксом `ship: gh: ` (до любого `leave`/`return`);
2) в шаблон временных ошибок добавить `HTTP 5[0-9][0-9]` и `Something went wrong`.
Остальное поведение не менять.

Критерии:
1) `grep -n "ship: gh: " bin/ship` → 1 строка в `gh_or70`
2) `grep -n "HTTP 5\[0-9\]\[0-9\]" bin/ship` → 1 строка
3) `bash -n bin/ship` → код 0

Паспорт источников: только код этого репо (`bin/ship:164-167`) и журнал курьера 06.10 22:45–22:49. Внешних API нет.
