# ТЗ dcfg-demsy.23.1 — disk-rotate: тихий restic forget и повтор тревоги раз в 24 ч
FILE: scripts/disk-rotate.sh
FILE: tests/disk-rotate-realert-test.sh (новый)
Проверка: `bash tests/disk-rotate-realert-test.sh` → последняя строка `AC4 pos=sent neg=skip`, rc 0.

## Зачем (замер 18.10)
1. `/var/log/disk-rotate.log` — 1.49 ГБ, растёт ~7 МБ за ежечасный прогон. Причина: вызов `"$RESTIC" forget --tag predelete --group-by host,tags --keep-within 10d --keep-tag keep-archive >>"$DR_LOG" 2>&1` печатает таблицы keep/remove всех снимков. restic 0.19.1 с `--quiet` таблицы не печатает (cmd_forget.go:278,287), ошибки остаются в stderr → в лог. Остальной вывод прогона ~15 КБ.
2. Тревога «диск занят … после уборки» (состояние `exhausted`) ушла 06.10 и с тех пор подавлена: `maybe_alert` при `alert_active` пишет `ALERT-SKIP <st> уже активен` навсегда, пока состояние не снято `clear_alert`. Диск 99%, напоминаний нет.

## Правка `scripts/disk-rotate.sh`
1. Добавить `--quiet` в этот вызов `restic forget` (только в него; аргументы, код возврата и ветка `forget-skipped` — как есть).
2. Повтор тревоги (ADR-1 v2 dcfg-demsy.23) — **только для состояния `exhausted`** (тревога «диск занят … даже после уборки»); все остальные состояния (`declared`, `s3`, `zone-silent:*`, `backup`, `summary`) ведут себя как сейчас: одна тревога до `clear_alert`:
   - рядом с остальными значениями `DR_*` по умолчанию: `DR_REALERT_SEC=${DR_REALERT_SEC:-86400}`;
   - `mark_alert` пишет `<состояние>=<epoch сейчас>` (`date +%s`) вместо `=active` (для всех состояний; `alert_active` по-прежнему проверяет только наличие записи);
   - `maybe_alert`: если `$st` = `exhausted`, запись есть и значение — число и `now - значение < DR_REALERT_SEC` → как сейчас `ALERT-SKIP $st уже активен`, return 0; если `$st` = `exhausted` и (возраст ≥ `DR_REALERT_SEC` или значение не число — старые `active` или дата `2026-10-06`) → отправить; при успехе `mark_alert` (свежий epoch); для остальных состояний логика `alert_active → ALERT-SKIP` не меняется; счётчики `ALERT_SENT`/`ALERT_FAIL` — как сейчас;
   - тексты тревог, `send_alert`, `clear_alert`, места вызова — без изменений.
3. Если скрипт нельзя подключить `source` без запуска основного прогона — добавить минимальный выход после определения функций по переменной (например `DR_SOURCE_ONLY=1` → `return 0` перед основным потоком). Обычный запуск (cron, dry-run, `DR_TEST_ONLY`) не меняется.

## Тест `tests/disk-rotate-realert-test.sh` (новый, `#!/bin/bash`, `set -u`, в стиле `scripts/disk-rotate-notify-test.sh`)
- Вызывает настоящую `maybe_alert` из `scripts/disk-rotate.sh` (не копию функций); `TMP=$(mktemp -d)`, `trap` удаляет его; `DR_LOG`, `DR_ALERT_STATE_FILE` — внутри `TMP`; `DR_NOTIFY_CMD` — заглушка в `TMP`, пишет текст в файл (поддельная отправка, Телеграм не вызывается, `/var/log` не трогается).
- pos: состояние `exhausted=<now-90000>` → `maybe_alert exhausted "текст"` → заглушка вызвана, epoch в файле обновлён → `pos=sent`.
- neg: `exhausted=<now-3600>` → заглушка не вызвана, в `DR_LOG` строка `ALERT-SKIP exhausted` → `neg=skip`.
- legacy: `exhausted=2026-10-06` → заглушка вызвана (иначе тест падает с понятной строкой).
- other: `backup=<now-90000>` → `maybe_alert backup "текст"` → заглушка НЕ вызвана (повтор только для `exhausted`; иначе тест падает с понятной строкой).
- Последняя строка вывода ровно `AC4 pos=<sent|skip> neg=<sent|skip>`; rc 0 только при `pos=sent neg=skip` и пройденных legacy и other.

## Запреты
Только эти 2 файла. Существующие тесты не менять. Пороги, классы уборки, гейт restic, тексты сообщений не менять. Секреты и `notify.env` не читать, реальную отправку не делать. Без `rm -rf` вне `TMP`, без коммита, push, PR.

## Готово, когда
`bash tests/disk-rotate-realert-test.sh` → `AC4 pos=sent neg=skip`, rc 0; `bash -n scripts/disk-rotate.sh` rc 0; `grep -c 'forget --quiet' scripts/disk-rotate.sh` = 1.
