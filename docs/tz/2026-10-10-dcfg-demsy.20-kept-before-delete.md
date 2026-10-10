# ТЗ dcfg-demsy.20 — класс backups удаляет файл только при копии с меткой keep-archive

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-028. Владелец 10.10: «Удаляем только то, что уже скопировано»; «Никогда не удалять файлы и данные без моего явного подтверждения — потеря необратима».
Дефект: копии прогона до dcfg-demsy.19 несут только метку `predelete`; `forget --keep-within 10d` сотрёт их через 10 дней, а файл уже удалён.
Паспорт источников: `restic snapshots --help` — «--json set output mode to JSON for commands that support it»; snapshot JSON содержит поле `tags` (вывод `restic snapshots --json` этого сервера, `disk-rotate.sh:559` читает тот же JSON-поток).
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, fail closed, минимальный дифф.

Файл: только `scripts/disk-rotate.sh`, функция `verify_and_delete`. Другие файлы не трогать, тесты не писать, disk-rotate.sh и тесты не запускать.

U1. Строка `local -A snap_path=() snap_done=()` → `local -A snap_path=() snap_done=() snap_kept=()`.

U2. В блоке `if [ -z "${snap_done[$snapshot_id]:-}" ]; then` сразу после `snap_done[$snapshot_id]=1` добавить:
```
      [ "$class" = backups ] && snap_kept[$snapshot_id]=$("$RESTIC" snapshots --json "$snapshot_id" 2>/dev/null \
        | jq -r '.[0].tags // [] | index("keep-archive") != null' 2>/dev/null)
```

U3. Сразу после закрывающего `fi` этого блока (перед `sid_path="$snapshot_id"$'\x1f'"$path"`) добавить:
```
    # backups: удаление только при бессрочной копии (keep-archive), иначе перефиксация с меткой (владелец 10.10)
    if [ "$class" = backups ] && [ "${snap_kept[$snapshot_id]:-}" != true ]; then
      journal_row "$class" snapshot-not-kept "$path" "$size" "$snapshot_id" - -
      REFIX_PATHS+=("$path")
      continue
    fi
```

Больше ничего не менять.

Запреты: `rm -rf` вне /tmp, сеть, другие файлы, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c snapshot-not-kept scripts/disk-rotate.sh` → 1
3) `git diff --stat` → 1 file changed
