# ТЗ dcfg-7pr9c — снимок формы видит новые файлы внутри неотслеживаемого каталога

Разведка — repowise: `repowise symbol "bin/code-channel::form_snap" --path /root/workspaces/tools`.
Паспорт источников: `form_snap()` в `bin/code-channel` (однострочная функция) берёт `git status --porcelain` без `--untracked-files=all`; git сворачивает неотслеживаемый каталог в одну строку `?? .agent-work/`, поэтому новый файл внутри него не меняет снимок → «form=… rc=0 без изменений» → лишние ступени (bd dcfg-7pr9c, dcfg-l2ru0).

## U1 — `bin/code-channel`, функция `form_snap`
Заменить `git status --porcelain` на `git status --porcelain --untracked-files=all`. Другой код не менять.

## U2 — `bin/code-channel-test`, проверка 45 в конце
Проект с уже существующим неотслеживаемым каталогом `.agent-work/` (в нём один файл); заглушка opencode rc 0 создаёт ещё один файл в `.agent-work/` → канал rc 0 и в stderr нет `без изменений`. Проверки 1–44 не менять; итог — `PASS 45/45`.

Не коммитить. Проверка (один прогон): `bin/code-channel-test` → `PASS 45/45`, FAIL нет.
