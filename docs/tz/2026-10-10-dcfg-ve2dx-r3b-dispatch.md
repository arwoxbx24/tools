# ТЗ dcfg-ve2dx r3b — dispatch:39 без exec

Остаток после r3a (FR-021, FR-030). Разведка — repowise: `repowise context git-hooks/dispatch --path /root/workspaces/tools`.

Только файл `git-hooks/dispatch` этого worktree.

## U1
1. Строка `:39` `exec "$hook" "$@" < "$tmp"` → две строки: `"$hook" "$@" < "$tmp"` и `exit $?`, отступ как у `:39`.
2. Строки `:47-48` (уже без `exec`) — отступ выровнять на 6 пробелов, как у соседних строк блока.
Другие строки не менять.

Проверка (один прогон): `bin/secret-gate-test` → `FAIL 0`.
