# ТЗ dcfg-m2lzu — ship: конфликт PR = отказ 50, а не «CI не появился» с бесконечным повтором

## U1 — проверка mergeable до ожидания CI
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

Причина (замер 09.10): `gh pr view 334 -R arwoxbx24/agent-contour --json state,mergeable` → `OPEN CONFLICTING` (атом dcfg-gured.2). При конфликте GitHub не запускает CI на pull_request. Тогда `ga_ci_wait` возвращает 30, а `bin/ship:157-158` выходит с `leave 30 ci-absent`. Дальше `bin/ship-post:322` при открытом PR (`rc == 22`) превращает 30 в 70 («временно») и повторяет без конца; задача в bd не появляется.

Решение (ADR):
1. `bin/ship`: перед `ga_ci_wait pr …` (`:155`) выполнить `mg=$(gh pr view "$num" -R "$slug" --json mergeable -q .mergeable 2>/dev/null)`. При `$mg == CONFLICTING`: `echo "ship: PR #$num конфликтует с $base — rebase ветки агента" >&2; leave 50 conflict`. `UNKNOWN`, `MERGEABLE` или пустой ответ — прежний путь.
2. `bin/ship-post:322`: убрать `[[ $rc == 22 ]] ||` из условия перевода 30 → 70. Временным считать только сетевые ошибки по уже существующему grep.
3. Всё остальное не менять.

Тесты:
- `bin/ship-test`: mock `gh` в тесте уже есть (строки 40-70). Добавить ответ на `pr view … --json mergeable`, переменная окружения `GH_MERGEABLE` (по умолчанию `MERGEABLE`). Новая проверка: `GH_MERGEABLE=CONFLICTING` → rc 50, merge не вызывался (по `$GH_JOURNAL`). Номер — следующий свободный.
- `bin/ship-post-test`: проверка, что ship rc 30 при открытом PR (`rc 22`) без сетевых строк в логе фиксируется как сбой 30, а не 70. Номер ≥130.
- Существующие проверки не ослаблять.

Запреты: только `bin/ship`, `bin/ship-test`, `bin/ship-post`, `bin/ship-post-test`; без `--force` и `rm -rf`. Принципы: KISS, fail fast.

Критерии:
1. `bash -n bin/ship bin/ship-post` rc 0.
2. `bin/ship-test` → `PASS N/N`, rc 0; `bin/ship-post-test` → `failures=0`, rc 0.
3. `grep -c 'leave 50 conflict' bin/ship` = 1.

Паспорт: `bin/ship:140-163`; `bin/ship-post:313-330`; `bin/git-auto-lib:121-166`; `gh pr view --json mergeable` проверен 09.10 выводом `OPEN CONFLICTING`.
