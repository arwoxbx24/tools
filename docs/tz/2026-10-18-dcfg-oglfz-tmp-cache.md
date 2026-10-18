# ТЗ dcfg-oglfz — disk-rotate: чистить /tmp и кэши каждый час, срок 1 сутки
FILE: scripts/disk-rotate.sh
FILE: tests/disk-rotate-tmp-test.sh (новый)
Проверка: `bash tests/disk-rotate-tmp-test.sh` → последняя строка `TMP-TEST pass`, rc 0.

## Зачем (слово владельца 18.10: «все кеши и temp — все папки должны чиститься быстрее и чаще»)
- `/tmp` отдан systemd-tmpfiles со сроком 30 дней (`scripts/disk-rotate.sh:773`); в /tmp 2802 записей верхнего уровня, из них 795 `disk-rotate-irr-*` — их создаёт сам скрипт (`:192` `IRR_LIST=$(mktemp /tmp/disk-rotate-irr-XXXX)`) и не удаляет.
- `cleanup_cache` (`:766`) чистит только 4 кэша и вызывается только при `soft`/`hard` (`:993-995`).

## Правка `scripts/disk-rotate.sh`
1. Свои временные файлы: `IRR_LIST` (`:192`) удалять при выходе скрипта (`trap … EXIT`, учесть уже существующие trap, если есть — объединить, не затирать). Остальные `mktemp` в функциях, если не удаляются сами, — так же.
2. Новая функция `cleanup_tmp`, вызывать из основного потока **каждый прогон** рядом с `cleanup_always` (в dry-run — только печать кандидатов):
   - только верхний уровень: `find -P /tmp -mindepth 1 -maxdepth 1 -mmin +"$DR_TMP_AGE_MIN" ! -type s -print0` — без обхода вглубь; `DR_TMP_AGE_MIN=${DR_TMP_AGE_MIN:-1440}` рядом с остальными `DR_*`; корень `/tmp` переопределяемый `DR_TMP_ROOT=${DR_TMP_ROOT:-/tmp}` (для теста);
   - исключить по имени: `tmux-*`, `claude-*`, `systemd-private-*`, `snap-private-tmp`, `restic-*`, `.X*`, `.ICE-unix`, `.font-unix`, `*.lock`, `*.pid`, `*.sock`;
   - исключить запись, если путь является cwd живого процесса или префиксом его cwd (один проход по `/proc/[0-9]*/cwd` через `readlink` до цикла, список в массив);
   - не больше `DR_TMP_MAX=${DR_TMP_MAX:-500}` записей за прогон;
   - удалять пачкой только через `"$TOOLS/bin/safe-delete" tmp <пути…>` (или как в скрипте уже вызывается safe-delete — тем же способом), под `nice -n 19 ionice -c3`; при `DR_TMP_ROOT` ≠ `/tmp` (тест) — удалять `rm -r --` внутри этого корня, т.к. safe-delete принимает только /tmp;
   - строка журнала через существующий `journal_row` (класс `tmp`), счётчик удалённых в `DR_LOG`; ошибка одной записи — не останавливает прогон.
3. Кэши: `cleanup_cache` вызывать **каждый прогон** (убрать условие `soft`/`hard` вокруг вызова на `:993-995`; `apt-get clean` и `journalctl --vacuum-size=200M` внутри остаются как есть). Добавить в него, тем же `clean_dir <путь> 1 cache`: `/root/.cache/go-build`, `/root/.cache/pnpm`, `/root/.cache/typescript`, `/root/.cache/mesa_shader_cache`, `/root/.cache/composer`, `/root/.cache/uv`. Не добавлять: `ms-playwright`, `huggingface`, `pre-commit`, `restic`, `opencode`, `claude*`, `codebase-memory-mcp`, `beads`, `kimi-code`, `mise`, `pw-mcp-profile` (установленный код/данные). Строку комментария `:773` заменить на одну строку: что /tmp чистит `cleanup_tmp`.
4. Если для теста нужно подключить скрипт без прогона — существующий `DR_SOURCE_ONLY` (PR #340) или аналог уже есть; использовать его.

## Тест `tests/disk-rotate-tmp-test.sh` (новый, `#!/bin/bash`, `set -u`, в стиле `tests/disk-rotate-realert-test.sh`)
- `DR_TMP_ROOT=$(mktemp -d)`, `trap` удаляет его; внутри: `old-dir/` и `old-file` с mtime 2 суток назад (`touch -d '2 days ago'`), `fresh-file` (сейчас), `tmux-0/` и `claude-0/` (старые), `x.lock` (старый), сокет (старый, через `python3 -c` socket bind), `busy/` (старый) — запустить `sleep 30 &` с `cd busy`, после теста `kill`.
- Вызвать настоящую `cleanup_tmp` в режиме run. Ожидание: удалены `old-dir`, `old-file`; остались `fresh-file`, `tmux-0`, `claude-0`, `x.lock`, сокет, `busy`. Каждое нарушение — строка `FAIL <имя>`.
- Последняя строка ровно `TMP-TEST pass` (rc 0) или `TMP-TEST fail` (rc 1). Настоящий `/tmp` не трогать.

## Запреты
Только эти 2 файла. Существующие тесты не менять. Пороги SOFT/HARD, классы, гейт restic, тексты тревог не менять. `/etc`, `/etc/tmpfiles.d`, crontab не трогать. Без `rm -rf` вне тестового корня, без коммита, push, PR. Секреты не читать.

## Готово, когда
`bash tests/disk-rotate-tmp-test.sh` → `TMP-TEST pass`, rc 0; `bash tests/disk-rotate-realert-test.sh | tail -1` → `AC4 pos=sent neg=skip`; `bash -n scripts/disk-rotate.sh` rc 0.
