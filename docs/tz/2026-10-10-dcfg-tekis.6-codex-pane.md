# ТЗ dcfg-tekis.6 — bd-inbox: окно tmux без TMUX_PANE (Codex)

Разведка — repowise (индекс tools: `tools/bin/code-memory-enable` уже сделан, dcfg-hd5at.8). Принципы: KISS, YAGNI, минимальный дифф, fail-open.

## U1
Skills: ponytail:ponytail

Проблема (замер 10.10): Codex v0.162.1 не передаёт `TMUX_PANE` в окружение своих команд (`env | grep -c "^TMUX_PANE="` → `0` в shell Codex), хотя у процесса codex он есть (`/proc/<pid>/environ`: `TMUX_PANE=%66`). `bin/bd-inbox:7` выходит при пустом `TMUX_PANE` → в Codex хук PostToolUse молчит.

Правка `bin/bd-inbox` (только строки 7–8, остальное не трогать):
- если `TMUX_PANE` задан — как сейчас: `tmux display-message -p -t "$TMUX_PANE" '#S:#I'`;
- иначе — найти окно по предкам процесса: взять таблицу `tmux list-panes -a -F '#{pane_pid} #S:#I'` (stderr → /dev/null), идти от `$PPID` вверх по `/proc/<pid>/stat` (поле 4 = ppid; либо `ps -o ppid= -p <pid>`) до pid 1, не больше 30 шагов; первый pid, совпавший с `pane_pid`, даёт окно;
- не нашли окно или tmux недоступен → `exit 0` без вывода (fail-open, как сейчас).
- В тестах таблицу панелей и цепочку предков подменять через переменные окружения (например `BD_INBOX_PANES` — готовая таблица вместо вызова tmux), без настоящего tmux.

Правка `bin/bd-inbox-test`: добавить 2 проверки к существующим 6:
7) `TMUX_PANE` пуст, таблица панелей содержит pid текущего предка с окном `cl:9`, stub bd отдаёт атом `metadata.tmux=cl:9` с комментарием «От …» → JSON с `additionalContext`;
8) `TMUX_PANE` пуст, в таблице нет ни одного предка → пустой вывод, rc 0.

Критерии:
1) `bin/bd-inbox-test` → `PASS 8/8`
2) `bin/bd-inbox --help` rc 0, usage на stdout
3) `env -u TMUX_PANE BD_INBOX_PANES='' bin/bd-inbox` → пусто, rc 0
4) `git diff --stat origin/main` — только `bin/bd-inbox`, `bin/bd-inbox-test`, этот ТЗ

Запреты: не трогать другие файлы, хуки и настройки; без сети; без записи в bd (только `bd list`/`bd comments` чтение); rm/рекурсивные chmod запрещены.
