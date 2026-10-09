# ТЗ dcfg-demsy.9 — полная проверка архива restic перед удалением

## U1 — gate_open: restic check

Разведка — repowise (индекс tools; нет — `tools/bin/code-memory-enable`). Файл: `scripts/disk-rotate.sh`, функция `gate_open` (около строки 410).

Факт 09.10: диск 99%, `code-archive` упал с `err:no-space`. disk-rotate запускается раз в сутки (04:00). Гейт удаления проверяет только `restic cat config`, это доступность репозитория, не его целостность.

Изменение (минимальное):
- В `gate_open` после проверки `cat config` добавить `"$RESTIC" check --retry-lock 10m >>"$DR_LOG" 2>&1`.
- При rc≠0: `GATE_REASON=restic-check-failed`, `return 1`.
- `restic check` без `--read-data` проверяет 100% структуры: индексы, паки, снимки. Чтение данных уже идёт ночью ротируемым subset (`pm2/server-backup.sh:467`), здесь его не повторять.
- Больше ничего не менять. Принципы: KISS, YAGNI, fail fast.

Источник: https://restic.readthedocs.io/en/stable/045_working_with_repos.html#checking-integrity-and-consistency — «restic check … will check the structural integrity and consistency of the repository».

Тест: в `scripts/tests/disk-rotate-gate-selfcheck.sh` добавить один случай по образцу соседних. Заглушка RESTIC: `cat config` даёт rc 0, `check` даёт rc 1. Ожидание: гейт закрыт (`restic-check-failed` в логе/журнале), ни один файл кандидата не удалён.

Запреты: `rm -rf` вне /tmp, без сети и живого restic в тесте, без правки crontab, без других файлов.

Проверка:
1) `bash -n scripts/disk-rotate.sh` rc 0
2) `grep -n "restic-check-failed" scripts/disk-rotate.sh` ≥1
3) `bash scripts/tests/disk-rotate-gate-selfcheck.sh` rc 0, новый случай PASS
