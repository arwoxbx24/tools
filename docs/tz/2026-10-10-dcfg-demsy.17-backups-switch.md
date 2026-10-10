# ТЗ dcfg-demsy.17 — disk-rotate: выключатель класса backups

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-032. Владелец 10.10: необратимое (удаление) — только после его подтверждения.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, YAGNI, fail fast (по умолчанию выключено), минимальный дифф.

Файл: только `scripts/disk-rotate.sh`. Другие файлы не трогать, тесты не писать, disk-rotate.sh и тесты не запускать.

U1. В начале функции `cleanup_backups()` (после строки `local -a els keep`) вставить:
```
  # FR-032: живой режим класса — только после подтверждения владельцем списка сухого прогона.
  if [ "$MODE" = run ] && [ "${DR_BACKUPS_APPROVED:-0}" != 1 ]; then
    echo "BACKUPS-HOLD нет DR_BACKUPS_APPROVED=1 — класс backups не трогается" >>"$DR_LOG"
    return 0
  fi
```
Больше ничего не менять.

Запреты: `rm -rf` вне /tmp, сеть, другие файлы, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c DR_BACKUPS_APPROVED scripts/disk-rotate.sh` → 2
3) `git diff --stat` → 1 file changed, 5 insertions(+)
