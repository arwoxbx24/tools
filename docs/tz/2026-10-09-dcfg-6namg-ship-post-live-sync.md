# ТЗ dcfg-6namg — ship-post: после доставки обновлять основную папку репо (git-sync)

## U1 — live sync после записи квитанции доставки
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

Причина (замер 09.10): после слияния PR основные папки отстают (`git -C /root/workspaces/tools status -sb` → `behind 3`, projects → `behind 9`). `ship-post` вызывает `ship --handover` (`bin/ship-post:306`), а `bin/ship:183` при `--handover` делает `leave 0 handover` до `ga_live_sync` (`bin/ship:189`, тело — `bin/git-auto-lib:183-193`: `"$bin/git-sync" "$name"`). Ни `ship-post`, ни cron `git-sync` не запускают: последняя запись `tools` в `logs/git-sync.log` — `2026-10-09T16:33:03 tools rescued …`, `projects err:checkout` в 14:05. Агенты работают на старых скриптах из основных папок.

Решение (ADR): одна точка — функция `write_delivery_receipt` (`bin/ship-post:275-283`), через неё проходят все успешные доставки (`:292`, `:311`, `:322`, а также пути `--watch` `:353,:359`). После `echo "delivered …"` добавить вызов live sync:
1. `name=$(basename "$repo")` — имена `ga_roots` для tools/projects совпадают с именем каталога. Комментарий `# ponytail: basename = имя ga_roots; при расхождении — git-sync даст err:ctx в выводе`.
2. `out=$("$bin/git-sync" "$name" 2>&1)`; при rc 0 — `echo "live $name: $out"`.
3. При rc ≠ 0 — `echo "ship-post: live sync $name failed: $out" >&2` и `bd_cmd update "$atom" --append-notes "ship-post live sync $name failed: $out"`; функция всё равно возвращает 0 (доставка в GitHub уже доказана квитанцией; падение sync видно в заметке атома и stderr).
4. `ship` и `git-sync` не менять.

Тест — `bin/ship-post-test`: mock `$d/bin/git-sync` (пишет `"$*"` в `$SHIP_POST_TEST_DIR/sync.calls`, rc из `${GIT_SYNC_RC:-0}`), создать в `make_mocks` рядом с mock `bd`, `chmod +x`. Новая функция `test_live_sync`, вызвать в общем списке; номера проверок ≥110 (не пересекаться с `case $n` строк 14-18 и A1-A4 100-103).
- L1: успешная доставка (взять существующий сценарий доставки, напр. как `test_delivery`) → в `sync.calls` ровно одна строка с именем каталога репо теста (`basename` от `$d/repo`).
- L2: тот же сценарий с `GIT_SYNC_RC=1` → доставка rc 0, в `bd.calls` есть `update <атом> --append-notes ship-post live sync … failed`.
- Существующие проверки не менять и не ослаблять.

Запреты: только `bin/ship-post` и `bin/ship-post-test`; без `--force`, `reset`, `rm -rf`; не трогать `ship`, `git-sync`, `git-auto-lib`; без новых зависимостей; соседний код не чистить. Принципы: KISS, YAGNI, fail fast.

Критерии:
1. `bash -n bin/ship-post` rc 0.
2. `bin/ship-post-test` → `failures=0`, rc 0, PASS L1 и L2.
3. `grep -c 'git-sync' bin/ship-post` ≥ 1.

Паспорт источников: `bin/ship:14,183-191`; `bin/git-auto-lib:183-193`; `bin/git-sync` хвост (usage `git-sync <name>|--all [--min-idle N]`); `bin/ship-post:67,275-324,353,359`; `bin/ship-post-test:52-94`.
