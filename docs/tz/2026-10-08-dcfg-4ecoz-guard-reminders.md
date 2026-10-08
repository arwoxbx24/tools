# ТЗ dcfg-4ecoz — forms-gw-guard: напоминания о длящемся сбое и «восстановлено»

Исполнитель: Codex (зона tools-кода) · Приёмка: Claude · Атом: dcfg-4ecoz (эпик dcfg-1ci20) · Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

## Факт (симптом)
`grep -E 'form_error|code=000' /root/.pm2/logs/forms-gw-guard-out-73.log`: 08.10 09:30:18 UTC `sent form_error`, далее 10 строк `debounced form_error` до 12:15:40. Владелец получил одно сообщение за 3 ч сбоя, сообщения о восстановлении не было.

## U1. Напоминания и восстановление
Файл: `tools/scripts/schedulers/forms-gw-guard.sh` (логика notify/debounce), тест: `tools/scripts/schedulers/forms-gw-guard-test.sh`.
1. Пока сбой длится, debounce не глушит навсегда: повторное сообщение не чаще интервала (переменная окружения с разумным значением по умолчанию, например 60 мин), в тексте — длительность сбоя с начала.
2. Переход из состояния сбоя в норму (например code 000 → 302) даёт одно сообщение «восстановлено» с длительностью сбоя.
3. Состояние — в существующем state-файле гвардa, без нового механизма хранения.

Принципы: SOLID, DRY, KISS, YAGNI, fail fast; минимальный дифф; соседний код не чистить.

Запрещено: рестарт pm2 и правка `ecosystem.config.js`; реальная отправка в Telegram из теста (только подменённая команда уведомления); чтение `/root/workspaces/secrets/**`, ключей, `auth.json`, `~/.codex/*.toml`, `~/.ssh/**`; `rm -rf` вне /tmp; `--force`; правка функции `arwox-lead-form` и шлюза. Системные запреты `/root/CLAUDE.md` в силе.

## Приёмка
1. `forms-gw-guard-test.sh`: сбой 3 ч → сообщений > 1 (начало + напоминания).
2. Переход 000 → 302 даёт сообщение «восстановлено».
3. `bash -n tools/scripts/schedulers/forms-gw-guard.sh` rc 0; прежние кейсы теста PASS.

## Доставка
Ветка/worktree `codex/dcfg-4ecoz-guard-reminders` в репо tools; копия этого ТЗ — в `docs/tz/` worktree (как у dcfg-q2o1e); `ship-post` и `bd close` НЕ вызывать: стоп на локальном коммите в worktree. Доклад: путь worktree, SHA, вывод теста. Приёмку (дифф + повтор теста) и `ship-post` делает Claude.
