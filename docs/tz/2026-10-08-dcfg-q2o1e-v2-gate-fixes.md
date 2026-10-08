# ТЗ v2 dcfg-q2o1e — дефекты моста projects в гейте disk-rotate (приёмка FAIL 08.10)

Исполнитель: Codex · Приёмка: Claude · Атомы: dcfg-q2o1e (родитель), dcfg-162rq · Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Worktree: `/root/workspaces/tools/.worktrees/claude/dcfg-q2o1e` (ветка `claude/dcfg-q2o1e-projects-gate`, база — коммит 43e9cc86). Один исправляющий коммит поверх.

## Причина v2 (verifier sonnet 08.10, коммит 43e9cc86)
1. `scripts/disk-rotate.sh:542-589` `verify_and_delete` обходит весь `DR_STATE_FILE` без фильтра класса: вызов для `projects` может удалить запись другого класса (`:577`).
2. `scripts/disk-zones/codex-worktrees.sh:44-45`: статус атома — `grep -q '"closed"'` по всему JSON `bd show`; совпадает с notes/связанными атомами.
3. `codex-worktrees.sh:50,55`: stderr `lsof` отброшен; rc=1 + пустой stdout + ошибка в stderr → `candidate`.
4. `disk-rotate.sh:766-768`: `git worktree remove` стирает ignored-файлы (`node_modules`, `.venv`, `__pycache__`, `dist`) без снимка restic.
5. dcfg-162rq: после удаления в том же прогоне удалённые пути снова уходят в `fix_candidates` (`:611-633`) → restic `Fatal: all source directories/files do not exist`, 384 ложных `deferred restic-backup-failed`.

## U1. Исправления (минимальный дифф)
1. `verify_and_delete` для класса трогает только записи своего класса; записи других классов не удаляются и не перемаркируются.
2. Статус атома — `jq` по точному `.id` и `.status == "closed"`.
3. `lsof`: свободен только при rc=1 И пустом stdout И пустом stderr; иначе `kept-lsof-error`.
4. Worktree с ignored-файлами (`git status --porcelain --ignored` непуст) — не удалять, строка `kept-ignored` (fail closed).
5. В список повторной фиксации не попадают несуществующие пути.

Принципы: SOLID, DRY, KISS, YAGNI, fail fast; переиспользовать гейт; второго механизма удаления нет; соседний код не чистить.

Запрещено: боевой запуск `disk-rotate.sh` (только selfcheck в песочнице и `--dry-run`); restic/yc/сеть; чтение `/root/workspaces/secrets/**`, ключей, `auth.json`, `~/.codex/*.toml`, `~/.ssh/**`; `rm -rf` вне /tmp; `--force`; `hh-scoring-dev/**`, `.claude/**`, `system/archives/**`, `client-materials/**`, `*.db`, `*-wal`; правка ZONE_MODE, pm2, cron. Системные запреты `/root/CLAUDE.md` в силе.

## Приёмка
1. `bash -n scripts/disk-rotate.sh scripts/disk-zones/codex-worktrees.sh` rc 0.
2. В `scripts/tests/disk-rotate-gate-selfcheck.sh` новые кейсы, каждый сначала красный на 43e9cc86, затем зелёный: (а) смешанный state legacy+projects — вызов projects не удаляет чужую запись; (б) JSON с `closed` только в notes → не eligible; (в) lsof rc=1 + stderr → kept; (г) worktree с ignored-файлом → kept-ignored, не удалён; (д) прогон 2 после удаления → 0 `deferred restic-backup-failed` по удалённым путям.
3. Прежние 17 кейсов PASS; итог `PASS N/N`, exit 0.

## Доставка
Локальный коммит в worktree с трейлерами `ТЗ: docs/tz/2026-10-08-dcfg-q2o1e-v2-gate-fixes.md#U1`, `Atom: dcfg-q2o1e`; копия ТЗ в `docs/tz/` worktree. `ship-post` и `bd close` НЕ вызывать. Доклад: SHA, вывод selfcheck (красный и зелёный).
