# ТЗ dcfg-l2ru0 r2 — снимок формы видит содержимое неотслеживаемых файлов

Остаток r1 (FR-030): r1 оборван сторожем FR-033 (откатан #221); его черновик проверки снят. Worktree на main 480c320.
Разведка — repowise: `repowise symbol "bin/code-channel::form_snap" --path /root/workspaces/tools`.
Факт (воспроизведено 10.10): `form_snap()` (`bin/code-channel:53`) — правка содержимого уже неотслеживаемого файла не меняет ни один из трёх выводов git → ложное «без изменений» → exit 16.

Только `bin/code-channel` и `bin/code-channel-test` этого worktree. Пробы, отладочные echo, каталоги и скрипты не создавать.

## U1 — сначала проверка (red)
`bin/code-channel-test`: новая проверка в конце, номер N — следующий после последней: в `$project` создать неотслеживаемый `.agent-work/untracked.txt` с `orig`; `CC_CONFIG=$go`, `OPENCODE_RC=0 OPENCODE_TOUCH=.agent-work/untracked.txt` → условие `[[ $rc == 0 ]] && ! grep -Fq -- "без изменений" "$tmp/err"`. Итоговую строку `PASS M/M` перевести на новое N. Прогнать → FAIL N.

## U2 — `bin/code-channel:53`, `form_snap`
Внутри группы `{ …; }` последней командой добавить `git ls-files -z --others --exclude-standard 2>/dev/null | xargs -0 -r cksum 2>/dev/null;`. Другое не менять.

Проверка (один прогон): `bin/code-channel-test` → `PASS N/N`. В отчёт — строку FAIL red-прогона дословно.
