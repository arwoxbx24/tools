# ТЗ dcfg-9jp05 — S3: образы Docker по одному, диск не кончается

разведка — repowise (индекс: repowise/CBM проверен для tools; нет — `tools/bin/code-memory-enable`), затем `grep -n`.
Принципы: KISS, YAGNI, fail fast, отказ одного образа не ломает остальные (`continue`, итог `ok=N failed=M`).
Править только `scripts/pm2/server-backup.sh` и `scripts/tests/server-backup-night-selfcheck.sh`. Второго скрипта и планировщика не создавать.

## U1

Факт (bd dcfg-9jp05, ветка `codex/dcfg-qjj5x.1-s3-docker` коммит 42a062b): один `docker image save` по всем 26 образам
заставил демон Docker сложить ~6.0 ГБ в `/var/lib/docker/tmp`; корень 100%; код откатан. В origin/main выгрузки образов нет
(`git grep -c backup_docker_images origin/main -- scripts/pm2/server-backup.sh` → пусто).
Замер 06.10: `df -B1 /` свободно 13537411072; самый большой образ 1.77GB (`docker image ls`), 26 образов.

Сделать в `scripts/pm2/server-backup.sh` функцию `backup_docker_images` (после `source "$S3_ENV"` и помощников):
1) Список: `docker image ls --no-trunc --quiet | LC_ALL=C sort -u`; каждый ID проверить `^sha256:[0-9a-f]{64}$`; пусто → лог, return 1.
2) Квитанция `$STAGE/docker-images.receipt`, строки `<id> <snapshot64>`. ID есть и `"$RESTIC" cat snapshot <snap>` код 0 → образ пропущен (ok++), без `docker save`. Образ по ID неизменен — повтор не нужен.
3) Перед каждым образом: `size=$(docker image inspect -f '{{.Size}}' "$id")`, `avail=$(df -B1 --output=avail /var/lib/docker | tail -1)`;
   `avail < size + ${BK_IMAGE_RESERVE_BYTES:-3221225472}` → лог `docker-images skip <id> low-space need=<n> avail=<n>`, failed++, `continue`.
4) Один образ за раз:
   `timeout -k 30s 3600 "${NICE_PREFIX[@]}" "$RESTIC" backup --json --tag docker-images --stdin-from-command --stdin-filename "docker-image-${id#sha256:}.tar.gz" --limit-upload "${BK_LIMIT_UPLOAD:-5120}" --retry-lock 30m -- env -u AWS_SECRET_ACCESS_KEY -u AWS_ACCESS_KEY_ID -u RESTIC_PASSWORD bash -o pipefail -c 'docker image save "$1" | gzip -1' _ "$id"`
   rc≠0 → лог, failed++, `continue`. Полный ID снимка: короткий `snapshot_id` из summary JSON → `restic snapshots --tag docker-images --json` → единственный с этим префиксом (как в 42a062b). Дописать строку в квитанцию.
5) После цикла: `run_step docker-images-retention ... forget --tag docker-images --group-by host,paths --keep-last 1 --retry-lock 30m` (без `--prune`: общий `forget --prune` стоит в :365).
6) Лог `docker-images ok=N failed=M count=K`; return 0 только при failed=0.
Вызов: аргумент `--images-only` → только `backup_docker_images || fail docker-images "$?"`, `exit 0` (до docker-stage). Обычный прогон — после docker-stage: `backup_docker_images; images_rc=$?`, сбой не останавливает обычную выгрузку; `images_rc` в строке SUMMARY и `fail docker-images` в конце, как в 42a062b.

Тест (`scripts/tests/server-backup-night-selfcheck.sh`, существующий стиль заглушек в `$TMP/bin` через PATH): заглушки docker (2 образа), df (мало места для второго), restic (успех) → лог содержит `low-space` и `ok=1 failed=1`; restic вызван ровно 1 раз с `--stdin-from-command`.

Критерии:
1) `bash -n scripts/pm2/server-backup.sh` → код 0
2) `grep -c 'docker image save "\$1"' scripts/pm2/server-backup.sh` → 1; `grep -c 'docker image save "\$@"' scripts/pm2/server-backup.sh` → 0
3) `grep -c 'BK_IMAGE_RESERVE_BYTES' scripts/pm2/server-backup.sh` → ≥1
4) `bash scripts/tests/server-backup-night-selfcheck.sh` → код 0

Паспорт источников: restic 0.19.1 (`/root/workspaces/tools/bin/restic version`), `restic backup --help`:
«--stdin-from-command  interpret arguments as command to execute and store its stdout»; «--stdin-filename filename  filename to use when reading from stdin»;
«Exit status is 3 if some source data could not be read (incomplete snapshot created)». Код репо: `server-backup.sh:5,10,16,27,47,108,365`; 42a062b (diff функции).
## U2 — тест штатного прогона (уточнение владельца v3)

Штатная ветка теста должна изолировать Docker producer через `BK_DOCKER_SCRIPT` (по умолчанию остаётся существующий `docker-backup.sh`), выдавать содержимое при заглушке `restic restore` и учитывать безопасный отказ локального удаления без owner gate. Разрешены изменения заглушек и сценариев только в существующем `scripts/tests/server-backup-night-selfcheck.sh`. В производственном скрипте разрешены U1 и одна строка `BK_DOCKER_SCRIPT`; другая логика не меняется.

Критерий: `bash scripts/tests/server-backup-night-selfcheck.sh` → код 0 (`PASS 14/14`). Запреты: секреты не читать, не создавать второй скрипт или планировщик, не останавливать чужие процессы, `rm -rf` вне `/tmp` не использовать.

## U3 — поток без gzip, атом dcfg-9jp05

Для репозитория restic формата 2 передавать вывод `docker image save` напрямую в существующий `restic backup --stdin-from-command`: имя `docker-image-<id>.tar`, `--compression auto`. Это сохраняет чанковую дедупликацию restic без предварительного gzip. Если формат 1, gzip сохраняется и причина фиксируется в атоме. Проверка 07.10: один короткий `restic cat config | jq -er .version` вернул `2` (rc 0); локальная справка `restic backup --help` подтверждает `--compression auto` для формата 2. Не запускать живые Docker/S3 тесты; один self-check на заглушках должен завершиться с кодом 0.

## U4 — тома Docker напрямую в restic, атом dcfg-lfief

В штатном ночном `server-backup.sh` включить `/var/lib/docker/volumes`, уже охваченные bind mounts и текущие `UpperDir` контейнеров Hiddify, proxy-manager и 3x-ui напрямую в один `restic backup`. В `docker-backup.sh` убрать `tar -czf` томов и bind mounts; дампы БД ежедневно атомарно обновлять в стабильном `/root/backups/docker/current`, не создавать новые датированные `20*` каталоги. Старые локальные архивы не удалять. Критерии: `tar -czf` для томов отсутствует; журнал и метаданные снимка подтверждают прямые пути; второй ночной снимок при неизменных томах добавляет менее 1 МБ данных томов; восстановление одного тома даёт совпадающие SHA-256 файлов; после ночи нет новых локальных `20*` каталогов. Новый скрипт или планировщик не добавлять; живые тяжёлые действия — только после 00:00.
