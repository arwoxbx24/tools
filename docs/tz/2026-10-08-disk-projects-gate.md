# ТЗ — spec:090 CR-03: зона projects через гейт S3 → удаление

Исполнитель: Codex (зона tools-кода) · Заказчик/приёмка: Claude · Спека: `specs/090-disk-zones-cache-compress/cr-03-projects-gate.md` (репозиторий projects, коммит 72b3ee2c7) · Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

## U1. Мост «кандидат зоны projects → существующий гейт»
Сделать FR-090-CR03-1…6 в `tools/scripts/disk-rotate.sh` (белый список путей вместо `projects/**` для `.agent-work` класса С и worktree ADR-090-7, передача в `fix_candidates`/`verify_and_delete`), `git worktree remove` без `--force` после строки гейта; строка S3 `used_size/max_size` и алерт ≥80% в ночном отчёте (`yc storage bucket stats --name arwox-server-backup --format json`).

Принципы: переиспользовать существующие функции гейта, без нового механизма удаления (YAGNI/KISS); fail fast на системных границах (restic, yc, git).

Запрещено: удаление без снимка `predelete` и проверки `restic ls`; `--force`; `hh-scoring-dev/**`, `secrets/**`, `.claude/**`, `system/archives/**`, `clients/**/client-materials/**`, `*.db`, `*-wal`; изменение бакета (lifecycle, lock, versioning); параллельные рестарты pm2; правка `ZONE_MODE` без ADR в bd. Системные запреты `/root/CLAUDE.md` в силе.

## Приёмка
1. `bash -n tools/scripts/disk-rotate.sh` rc 0; selfcheck гейта PASS.
2. `--dry-run`: список кандидатов `projects` только из белого списка; `grep -cE 'hh-scoring-dev|secrets|client-materials|\.db$|-wal$'` по списку = 0.
3. Одна живая ночь (или ручной прогон `GATE_MODE=enforce` по штатной обёртке): строки `deleted` по `projects` с `snapshot_id`; `restic ls <snapshot_id>` содержит путь.
4. `git worktree list | wc -l` до/после; у оставшихся — `kept-<причина>`.
5. `df -h /` до/после; строка S3 % в отчёте.
6. ship-post SHA, `bd close` с командами и цифрами.

## Источники
- Факты причины — `cr-03-projects-gate.md` §«Глобальная причина» (команды и строки).
- restic `ls` — уже используется гейтом `disk-rotate.sh:549`; синтаксис сверить по https://restic.readthedocs.io (цитата не снята — не проверено).
- git (WebFetch 08.10): https://git-scm.com/docs/git-worktree — «remove … Only clean worktrees (no untracked files and no modification in tracked files) can be removed. Unclean worktrees or ones with submodules can be removed with --force» (без `--force` грязный не удаляется).
