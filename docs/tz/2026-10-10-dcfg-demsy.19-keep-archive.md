# ТЗ dcfg-demsy.19 — копии класса backups в S3 хранятся бессрочно

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-028. Владелец 10.10: «Удаляем только то, что уже скопировано».
Дефект: `forget --tag predelete --group-by host,tags --keep-within 10d` удаляет через 10 дней единственную копию удалённых бэкапов.
Паспорт источников: `restic forget --help` — «--keep-tag taglist  keep snapshots with this taglist»; `restic backup --help` — «--tag tags  add tags for the new snapshot in the format `tag[,tag,...]`».
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, минимальный дифф.

Файл: только `scripts/disk-rotate.sh`. Другие файлы не трогать, тесты не писать, disk-rotate.sh и тесты не запускать.

U1. В `fix_candidates` строка `dump=$("$RESTIC" backup --files-from-verbatim "$fix_list" --tag predelete --host ...)`: метка зависит от класса. Перед этой строкой добавить
```
  local tags=predelete
  # backups: копия — единственная после удаления, forget её не трогает (владелец 10.10)
  [ "$class" = backups ] && tags=predelete,keep-archive
```
и в самой строке заменить `--tag predelete` на `--tag "$tags"`.

U2. В строке `"$RESTIC" forget --tag predelete --group-by host,tags --keep-within 10d` добавить `--keep-tag keep-archive` после `--keep-within 10d`.

Больше ничего не менять.

Запреты: `rm -rf` вне /tmp, сеть, другие файлы, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c keep-archive scripts/disk-rotate.sh` → 2 (v2: метка в строке `tags=` и в `--keep-tag`; комментарий её не содержит)
3) `git diff --stat` → 1 file changed
