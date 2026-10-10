# ТЗ dcfg-demsy.12 — disk-rotate: убрать класс codex-sessions

Спека: `specs/054-server-attestation/spec.md` CR 2026-10-10, FR-031. Владелец 10.10: «удаляем только бэкапы. Рабочие директории ни в коем случае трогать нельзя». Сессии Codex — рабочие данные.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Принципы: KISS, YAGNI, минимальный дифф. Комментарии к неизменённому коду не трогать.

Файлы: `scripts/disk-rotate.sh` (U1), `scripts/tests/disk-rotate-gate-selfcheck.sh` (U2). Другие файлы не трогать.

U1. Удалить класс `codex-sessions` целиком, классы `codex-review` и `codex-releases` не менять:
- в массиве `CODEX_ALLOW` удалить строку `"$DR_CODEX_HOME/sessions"`;
- в `verify_and_delete` удалить ветку `codex-sessions) ... ;;` в `case "$class"`;
- в `cleanup_codex` удалить переменную `sessions` из `local` и блок `# codex-sessions: ...` (`if [ -d "$sessions" ]; then ... fi`) целиком;
- в комментарии над `cleanup_codex` заменить «сессии незаменимые — через гейт» на «сессии Codex не трогаются (владелец 10.10)».

U2 (ТЗ v2 — причина: самопроверка ждёт старого поведения). U1 уже сделан в worktree — не повторять. В `scripts/tests/disk-rotate-gate-selfcheck.sh` функция `scenario_26` (строки 683–696): фикстура и `run_rotate` без изменений; комментарий функции → `# старая сессия Codex не фиксируется и не удаляется (владелец 10.10)`; условие PASS заменить на:
```
  if [ -f "$session" ] && ! grep -qF "$session" "$STATE" 2>/dev/null \
     && ! grep -q 'codex-sessions' "$JOURNAL" 2>/dev/null; then
    report 26 "codex sessions untouched" PASS
  else
    report 26 "codex sessions untouched" FAIL
  fi
```

Запреты: `rm -rf` вне /tmp, сеть, файлы кроме двух названных, git push.

Проверка:
1) `bash -n scripts/disk-rotate.sh` → rc 0
2) `grep -c codex-sessions scripts/disk-rotate.sh` → 0
3) `grep -c 'codex-review' scripts/disk-rotate.sh` → не меньше 2
4) `git diff --stat` → 2 files changed
5) `bash -n scripts/tests/disk-rotate-gate-selfcheck.sh` → rc 0; `grep -c 'codex sessions untouched' scripts/tests/disk-rotate-gate-selfcheck.sh` → 2
