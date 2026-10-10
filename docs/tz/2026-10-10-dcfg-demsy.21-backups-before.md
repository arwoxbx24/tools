# ТЗ dcfg-demsy.21 — класс backups только для бэкапов старше даты подтверждения

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-032. Владелец 10.10 13:35 «yes» на вопрос «удалить старые бэкапы (~4,2 ГБ) после копии в S3?» — подтверждены только старые бэкапы.
Дефект: правила класса действуют каждый час бессрочно; новый бэкап уходит в S3 с меткой keep-archive и удаляется с диска — S3 растёт без предела.
Паспорт источников: `stat --help` — «%Y time of last data modification, seconds since Epoch»; эпоха подтверждения `date -d '2026-10-10 13:35' +%s` = 1791628500.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, fail closed (нет переменной — класс ничего не берёт), минимальный дифф.

Файл: только `scripts/disk-rotate.sh`, функция `cleanup_backups`. Другие файлы не трогать, тесты не писать, disk-rotate.sh и тесты не запускать.

U1. В `cleanup_backups` цикл `for el in $mask; do` заменить тело
```
      [ -e "$el" ] && [ ! -L "$el" ] || continue
      els+=("$(stat -c %Y "$el" 2>/dev/null || echo 0)"$'\t'"$el")
```
на
```
      [ -e "$el" ] && [ ! -L "$el" ] || continue
      mt=$(stat -c %Y "$el" 2>/dev/null || echo 0)
      # только бэкапы старше подтверждения владельца (10.10 13:35); новые не трогаются
      [ "$mt" -lt "${DR_BACKUPS_BEFORE:-0}" ] || continue
      els+=("$mt"$'\t'"$el")
```

Больше ничего не менять.

Запреты: `rm -rf` вне /tmp, сеть, другие файлы, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c DR_BACKUPS_BEFORE scripts/disk-rotate.sh` → 1
3) `git diff --stat` → 1 file changed
