# ТЗ dcfg-l2ru0 — снимок формы видит содержимое неотслеживаемых файлов

Разведка — repowise: `repowise symbol "bin/code-channel::form_snap" --path /root/workspaces/tools`.
Факт (воспроизведено 10.10 на main 6f78bfc): `form_snap()` (`bin/code-channel:84`) собирает `git rev-parse HEAD`, `git status --porcelain --untracked-files=all`, `git diff HEAD`. Если правится содержимое уже неотслеживаемого файла, все три вывода прежние → снимок одинаков → ложное «rc=0 без изменений» → exit 16.

Только `bin/code-channel` и `bin/code-channel-test` этого worktree. Пробы, каталоги и скрипты не создавать — сразу правка.

## U1 — `bin/code-channel-test`, новая проверка в конце (сначала она)
git-проект с одним неотслеживаемым файлом; заглушка opencode rc 0 меняет содержимое этого файла → канал rc 0, в stderr нет `без изменений`. Номер — следующий после последней проверки, итог `PASS N/N` под новое N. Прогнать тест до U2 → FAIL новой проверки (red).

## U2 — `bin/code-channel`, `form_snap`
Внутри группы `{ …; }` добавить последней командой: `git ls-files -z --others --exclude-standard 2>/dev/null | xargs -0 -r cksum 2>/dev/null`. Другое не менять.

Проверка (один прогон после U2): `bin/code-channel-test` → `PASS N/N`, FAIL нет. В отчёт — строку FAIL red-прогона дословно.
