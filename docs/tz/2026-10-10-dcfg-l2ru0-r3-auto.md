# ТЗ dcfg-l2ru0 r3 — остаток: проверка через auto + правка form_snap

Остаток r2 (FR-030). Факт: `bin/code-channel:249-251` — форма, отличная от `auto`/`audit`, обходит снимок «до/после» (`:265-277`); проверка 47 вызывает `code-channel go` → проходит и без фикса (ошибка ТЗ r2).
Разведка не нужна: правки точечные, строки указаны.

Только `bin/code-channel` и `bin/code-channel-test` этого worktree. Тесты НЕ запускать, пробы не делать — их прогоняет оркестратор.

## U1 — `bin/code-channel-test`, проверка 47
В строке команды проверки 47 (`… OPENCODE_TOUCH=.agent-work/untracked.txt … "$root/bin/code-channel" go "$project" "$tz"`) заменить `go` на `auto`. Больше в тесте ничего не менять.

## U2 — `bin/code-channel:53`, `form_snap`
Внутри группы `{ …; }` после `git diff HEAD 2>/dev/null;` добавить `git ls-files -z --others --exclude-standard 2>/dev/null | xargs -0 -r cksum 2>/dev/null;`. Другое не менять.
