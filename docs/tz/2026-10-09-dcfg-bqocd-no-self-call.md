# ТЗ dcfg-bqocd — исполнитель формы 2 не вызывает code-channel сам

## U1 — строка пролога «ты уже внутри code-channel»
ВНИМАНИЕ ИСПОЛНИТЕЛЮ: ты уже запущен внутри `code-channel`. Правь файлы сам (apply_patch/редактор). `code-channel`, `opencode run`, `codex exec` НЕ вызывать — вложенный вызов падает `Read-only file system`.

Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Причина (замер 09.10): сессия codex 01a12122 (атом dcfg-fl9er.5.3) — 17 вызовов `code-channel auto` изнутри формы 2, итог BLOCKED rc=24, git diff пуст в 2 прогонах; тот же дефект 03.10 (dcfg-95ino).

Файлы (только эти): `bin/code-channel`, `bin/code-channel-test`.

1. `bin/code-channel`, ветка `if [[ $n == 2 ]]` (сейчас строки 91–92): ПЕРЕД строкой `prompt=$(printf 'Не создавай и не переключай ветки…` добавить одну строку той же формы:
```bash
        prompt=$(printf 'Ты уже исполнитель внутри code-channel: правь файлы сам; code-channel, opencode run, codex exec не вызывай\n\n%s' "$prompt")
```
Порядок существующих двух строк не менять (кейс 16 теста ждёт строку про bd сразу после аргументов codex).
2. `bin/code-channel-test`, кейс 16: в условие `check 16 '…'` добавить ещё один `&& grep -Fq -- "Ты уже исполнитель внутри code-channel: правь файлы сам; code-channel, opencode run, codex exec не вызывай" "$log"`. Остальные кейсы не трогать.
- Больше ничего не менять. Без хелперов (KISS, YAGNI).

Проверка (выполнить, вывод — в отчёт):
1. `bash bin/code-channel-test` → rc 0, кейс 16 PASS.
2. `grep -c 'Ты уже исполнитель внутри code-channel' bin/code-channel` → 1.
3. `git diff --stat` — ровно 2 файла.
Принципы: SOLID, DRY, KISS, YAGNI; без чистки соседнего кода.
