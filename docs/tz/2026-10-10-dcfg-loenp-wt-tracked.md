# ТЗ dcfg-loenp — safe-delete worktree: не проверять сегменты у git-чистых файлов

Разведка — repowise; индекс: repowise/CBM проверен (tools, dcfg-hd5at.8). Принципы: KISS, YAGNI, минимальный дифф, fail fast.

## U1
Skills: ponytail:ponytail

Проблема (замер 10.10): `safe-delete worktree <слитый worktree>` → rc 2 «запрещённый сегмент: …/.beads/config.yaml» (и `.repowise/config.yaml`). Причина — `bin/safe-delete:109`: `check_file` вызывается для каждого файла worktree, включая git-чистые. Git-чистые файлы не удаляются по одному (строка 112 `git_file "$f" || delete_file`) и сохраняются ref `refs/safe-delete/wt-*` (строки 110–111), поэтому проверка сегментов для них лишняя.

Правка `bin/safe-delete`, только строка 109:
`for f in "${files[@]}"; do check_file "$f"; done` → `for f in "${files[@]}"; do git_file "$f" || check_file "$f"; done`
Остальное не трогать. Незакоммиченные/изменённые файлы проверяются как раньше (под `.beads`/`.repowise`/`secrets` — отказ rc 2).

Правка `bin/safe-delete-test`: перед итоговой строкой добавить 2 проверки и поднять итог `[[ $ok == 42 ]]` → `[[ $ok == 44 ]]`:
- T43: worktree от `$d/w` с закоммиченным `.beads/config.yaml` (коммит в ветке worktree) → `safe-delete --bk "$bk" worktree` rc 0, каталога нет.
- T44: worktree с незакоммиченным файлом `.beads/x` → rc 2, `err` содержит «запрещённый сегмент», каталог на месте (после — `git worktree remove --force` как в T36).

Критерии:
1) `bin/safe-delete-test` → rc 0, `grep -c '^PASS'` = 44, `FAIL` = 0
2) `bin/safe-delete --help` rc 0
3) `git diff --stat origin/main` — только `bin/safe-delete`, `bin/safe-delete-test`, этот ТЗ

Запреты: другие файлы, хуки, настройки не трогать; без сети; без коммита (коммит делает ship-post); rm -rf вне /tmp запрещён; настоящие worktree вне временного каталога теста не удалять.
