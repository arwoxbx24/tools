# ТЗ dcfg-fkwsp — safe-delete worktree: минуты → секунды

Разведка — repowise; индекс: repowise/CBM проверен (tools, dcfg-hd5at.8). Принципы: KISS, YAGNI, минимальный дифф, fail fast.

## U1
Skills: ponytail:ponytail

Проблема (замер 10.10): `safe-delete worktree` на копии projects (~2000 отслеживаемых файлов) идёт минуты. Причина — `bin/safe-delete:109` и `:112`: `git_file` (≈8 git-процессов) вызывается на КАЖДЫЙ файл worktree.

Правка `bin/safe-delete`, только ветка `worktree)`:
- один раз собрать «грязные» пути worktree (NUL-разделитель): `git -C "$wt" ls-files -z --others` (неотслеживаемые и игнорируемые), `git -C "$wt" ls-files -z --modified`, `git -C "$wt" diff -z --name-only --cached HEAD`; пути абсолютные `"$wt/<rel>"`.
- строки 109 и 112 обходят только эти пути (существующие обычные файлы) вместо всего `find`: 109 — `git_file "$f" || check_file "$f"`, 112 — `git_file "$f" || delete_file "$f" || exit 1`, как сейчас. Чистые отслеживаемые файлы не проверяются и не копируются — их сохраняет ref `refs/safe-delete/wt-*` (строки 110–111, без изменений).
- остальное (проверка процессов, ref, `worktree remove`, лог) не трогать.

Правка `bin/safe-delete-test`: существующие 44 проверки без изменений, все PASS (T37 — грязный worktree с копией, T43, T44 — обязательно).

Критерии:
1) `bin/safe-delete-test` → rc 0, `grep -c '^PASS'` = 44, `FAIL` = 0
2) `bin/safe-delete --help` rc 0
3) `git diff --stat origin/main` — только `bin/safe-delete`, этот ТЗ

Запреты: другие файлы, хуки, настройки не трогать; без сети; без коммита; rm -rf вне /tmp запрещён; настоящие worktree вне временного каталога теста не удалять.
