# ТЗ dcfg-tekis.2 — bd-inbox: комментарии других агентов в контекст без прерывания

Рабочая копия: `/root/workspaces/tools/.worktrees/claude/dcfg-tekis.2`. Пути указаны от неё.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`. Новые файлы, чужой код не читать.

## Зачем
Агент A работает в атоме bd. Агент B пишет в атом комментарий `bd comments add <атом> "От …"`. Сейчас A его не видит, пока сам не прочтёт. Толкать A в окно tmux запрещено: это прерывает работу.
Решение: хук PostToolUse (Claude и Codex) после каждого вызова Bash запускает `bin/bd-inbox`. Скрипт отдаёт новые комментарии в контекст агента. Токены тратятся только при наличии комментария.

## Что сделать
### 1. `bin/bd-inbox` (bash + jq, новый файл, исполняемый, ≤60 строк)
- `--help` или `-h` → usage на stdout, rc 0, без других действий.
- stdin (JSON хука) не читать и не нужен.
- Своё окно: `win=${BD_INBOX_WINDOW:-$(tmux display-message -p -t "$TMUX_PANE" '#S:#I')}`. `TMUX_PANE` пуст или результат пуст → выход rc 0 без вывода.
- bd: `BD=${BD_BIN:-bd}`. База одна — всегда `"$BD" -C /root/workspaces/projects …` (хук работает из любой папки).
- Свои атомы: `"$BD" -C /root/workspaces/projects list --status in_progress --limit 0 --json -q` → jq: элементы, где `.metadata.tmux == $win` и `.comment_count > 0` → `.id`.
- По каждому id: `"$BD" -C /root/workspaces/projects comments <id> --json`. Поля элемента: `text`, `created_at` (ISO, строки сравнимы).
  - `last` = наибольший `created_at` среди комментариев, где `text` начинается с `принято:` или `вне цели:`; нет таких → пустая строка.
  - Ждут ответа: `text` начинается с `От ` и `created_at > last`.
  - Строка вывода: `<id>: <text>`; `text` обрезать до 500 символов.
- Есть хотя бы одна строка → на stdout ровно один JSON (через `jq -n`):
  `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<текст>"}}`.
  Текст: первая строка `Комментарии других агентов в твоих атомах — ответь bd comments add <атом> "принято: …" или "вне цели: CR <id>":`, далее строки `<id>: <text>`.
- Нет строк → stdout пуст.
- Любая ошибка (bd, jq, tmux) → stdout пуст, rc 0 (fail-open: хук не ломает работу агента). Без `set -e`.
- Код выхода всегда 0.

### 2. `bin/bd-inbox-test` (bash, новый файл, исполняемый)
Подставной bd: во временном каталоге `mktemp -d` файл-заглушка, которая по аргументам `list` и `comments <id>` печатает заранее заданный JSON. Передавать через `BD_BIN`, окно — через `BD_INBOX_WINDOW`.
Проверки:
1. `bin/bd-inbox --help` → rc 0, stdout содержит `usage`.
2. Без окна (`BD_INBOX_WINDOW` пуст, `TMUX_PANE` пуст) → rc 0, stdout пуст.
3. Атом `t-1` с `metadata.tmux` = окно, `comment_count` 1, комментарий `От X: факт` без ответа → rc 0; `jq -r .hookSpecificOutput.additionalContext` содержит `t-1: От X: факт`; `hookEventName` = `PostToolUse`.
4. Тот же атом и позже `принято: ок` → stdout пуст.
5. Атом с чужим окном → stdout пуст.
6. Заглушка bd выходит с rc 1 → rc 0, stdout пуст.
Финальная строка: `PASS 6/6`, иначе `FAIL <номер>` и rc 1.

## Проверка (вывод — в отчёт)
1) `bash bin/bd-inbox-test` → `PASS 6/6`
2) `bash -n bin/bd-inbox` → rc 0
3) `wc -l bin/bd-inbox` → ≤60

## Паспорт источников
- Claude Code hooks (code.claude.com/docs/en/hooks): PostToolUse поддерживает `hookSpecificOutput.additionalContext` — текст добавляется в контекст Claude.
- Codex hooks (learn.chatgpt.com/docs/hooks): «That `additionalContext` text is added as extra developer context.»; «Plain text on `stdout` is ignored» для PostToolUse; shell-инструмент — «Match as `Bash`»; «Commands run with the session `cwd` as their working directory.»
- bd 1.3.0: `bd comments <id> --json` → массив `{id, issue_id, author, text, created_at}` (замер 10.10 на dcfg-yle3s.4); `bd list --json` несёт `comment_count` и `metadata` (замер 10.10).
- tmux: `display-message -p -t <pane> '#S:#I'` → `cl:6` (замер 10.10).
- Других внешних вызовов нет. Вызов вне паспорта или вторая ошибка подряд → status blocked.

## Принципы
KISS, YAGNI: без кэша, без конфигов, без логов. Один скрипт и один тест.

## Правила исполнителя
- Не делать git add/commit. Не вызывать code-channel, opencode run, codex exec, настоящий bd, tmux-send. Ветки не трогать.
- Запрещено: rm -rf вне /tmp, chmod -R, ~/.ssh, iptables, curl|bash, глобальные пакеты, чтение секретов.
