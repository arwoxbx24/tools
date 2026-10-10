# ТЗ dcfg-demsy.18 — правило backups для датированных docker-снимков

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-029a v2. Владелец 10.10 «yes» на удаление старых бэкапов после копии в S3.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, минимальный дифф.

Файл: только `scripts/disk-rotate.sh`. Другие файлы не трогать, тесты не писать, disk-rotate.sh и тесты не запускать.

U1. В массиве `BACKUP_RULES` первой строкой (перед `'0|/root/backups/hh-scoring-snapshots/*.tar.gz'`) добавить:
```
  '0|/root/backups/docker/20*_*'
```
Больше ничего не менять.

Запреты: `rm -rf` вне /tmp, сеть, другие файлы, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c "'0|/root/backups/docker/20\*_\*'" scripts/disk-rotate.sh` → 1
3) `git diff --stat` → 1 file changed, 1 insertion(+)
