# ТЗ dcfg-demsy.13 — disk-rotate: класс backups по списку правил

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-027, FR-028, FR-029, FR-029a, FR-032. Владелец 10.10: «удаляем только бэкапы», «Удаляем только то, что уже скопировано», «Стабильно работать и не ломаться».
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, YAGNI, DRY (переиспользовать `handle`, `gate_process`, `verify_and_delete`), fail fast, минимальный дифф. Комментарии к неизменённому коду не трогать.

Паспорт источников: образец класса через гейт — `cleanup_codex` (ветка codex-sessions в истории `a6f50c8`, `scripts/disk-rotate.sh`): в `run` — список путей в файл и `gate_process <class> <list> || true`; в `dry-run` — `handle <class> < <(… -print0)`. Гейт: `fix_candidates` (копия restic tag predelete), `verify_and_delete` (сверка size+mtime+sha256, удаление следующим прогоном).

Файлы: `scripts/disk-rotate.sh` (U1–U6), `scripts/tests/disk-rotate-selfcheck.sh` (U7). Другие файлы не трогать. Тесты и disk-rotate.sh не запускать.

U1. Рядом с `CODEX_ALLOW` добавить массив правил (одна строка = вид бэкапа, формат `N|маска`, N — сколько новейших держать локально):
```
# Класс backups (spec:054 CR FR-027/029, владелец 10.10): N|маска; N новейших остаются локально,
# остальные — только через гейт restic. Новый вид бэкапа = одна строка.
BACKUP_RULES=(
  '0|/root/backups/hh-scoring-snapshots/*.tar.gz'
  '1|/root/workspaces/projects/rss-tg-ins/data/backups/rss-tg-ins-*.tar.gz'
  '0|/root/workspaces/projects/stroyremont/*backup*.sql'
  '0|/root/workspaces/projects/stroyremont/backups/*.sql'
  '0|/root/workspaces/system/infra/minio-b244/minio_backup_*.tar.gz'
  '0|/root/workspaces/system/archives/*'
)
```

U2. Функция `backup_rule_match() { # path -> 0, если путь — элемент маски правила или файл внутри такого элемента`. Сравнение через `[[ "$path" == $glob ]]` и `[[ "$path" == $glob/* ]]` для каждого правила.

U3. В `denied()` первой строкой: `backup_rule_match "$p" && return 1` (правила сильнее NEVER_LIST и DENY_LIST, но только для своих масок).

U4. В `verify_and_delete` в `case "$class"` добавить ветку `backups) backup_rule_match "$path" && own=1 ;;`.

U5. Функция `cleanup_backups()`: для каждого правила — элементы маски (только существующие, не симлинки), сортировка по mtime от новых к старым, первые N пропустить; для оставшихся элементов — регулярные файлы (`find -P <элемент> -type f`; для файла — он сам). Режим `run`: пути в временный файл → `gate_process backups "$list" || true` → удалить временный файл → `find <элемент> -type d -empty -delete` только для элементов-каталогов. Режим `dry-run`: `handle backups < <(… -print0)`. Один сбой правила не прерывает остальные (`continue`).

U6. Вызов `cleanup_backups` сразу после `cleanup_codex` в ветке `elif [ "$MODE" != report ]` (сейчас строка ~912). В тестовой ветке (`DR_TEST_ONLY`) не вызывать.

U7 (ТЗ v2 — причина: `scripts/tests/disk-rotate-selfcheck.sh` падает на 2 инвариантах). U1–U6 уже сделаны в worktree — не повторять. В `scripts/tests/disk-rotate-selfcheck.sh`:
- инвариант 2 (строка ~36): проверять только строки кандидатов, чей класс (4-я колонка TSV) не `backups` и не начинается с `codex-` — эти классы разрешены владельцем 10.10 и идут через гейт. Форма: `if awk -F'\t' '$4!="backups" && $4 !~ /^codex-/' "$TMP/dry1.out" | grep -qE '/root/backups|/root/.codex|hh-scoring|secrets/'; then` … (FAIL/PASS ветки без изменений);
- инвариант 3 (строка ~44): сравнивать набор кандидатов, а не живые величины: `if cmp -s <(grep -v 'closed zone' "$TMP/dry1.out" | cut -f1,4) <(grep -v 'closed zone' "$TMP/dry2.out" | cut -f1,4); then` (размер живого `hh-scoring-dev` и возраст в сутках меняются между прогонами).

Запреты: `/root/backups/docker/**` не входит (FR-029a); `rm -rf` вне /tmp; сеть; другие файлы; git push; живой прогон без `--dry-run` запрещён.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c 'cleanup_backups' scripts/disk-rotate.sh` → 2
3) `grep -c "^  '[0-9]|/" scripts/disk-rotate.sh` → 6
4) `git diff --stat` → 2 files changed (`scripts/disk-rotate.sh`, `scripts/tests/disk-rotate-selfcheck.sh`)
5) `bash -n scripts/tests/disk-rotate-selfcheck.sh` → rc 0
