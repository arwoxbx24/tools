# ТЗ dcfg-3hi9u — spec:090 CR-03: запуск классификатора worktree через bash

Атом: dcfg-3hi9u (находка от dcfg-q2o1e). Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

## U1. Префикс bash
Файл `scripts/disk-rotate.sh`, строка 739. Сейчас скрипт `scripts/disk-zones/codex-worktrees.sh` (git mode 100644, не исполняемый) вызывается как `"$self_dir/disk-zones/codex-worktrees.sh"` → `Permission denied` → `projects classifier failed`.
Заменить вызов на `bash "$self_dir/disk-zones/codex-worktrees.sh"`. Больше ничего не менять: ни другие строки, ни права файлов, ни `ZONE_MODE`.

Принципы: KISS, YAGNI — одна строка; багфикс не чистит соседний код.

Запрещено: удаление файлов, `--force`, `chmod`, правка `ZONE_MODE`, живой прогон `GATE_MODE=enforce`, git commit, правка вне `scripts/disk-rotate.sh`. Системные запреты `/root/CLAUDE.md` в силе.

## Приёмка
1. `grep -c 'bash "$self_dir/disk-zones/codex-worktrees.sh"' scripts/disk-rotate.sh` = 1.
2. `bash -n scripts/disk-rotate.sh` rc 0.
3. `bash scripts/tests/disk-rotate-gate-selfcheck.sh` → PASS 17/17.

## Источники
- Факт дефекта: `git ls-files -s scripts/disk-zones/codex-worktrees.sh` → `100644`; `grep -n codex-worktrees.sh scripts/disk-rotate.sh` → строка 739 без `bash` (08.10, эта сессия).
- bash(1) man: «If arguments remain after option processing … the first argument is assumed to be the name of a file containing shell commands» — https://www.gnu.org/software/bash/manual/bash.html#Invoking-Bash (цитата не снята в этом ходе — не проверено).
