# ТЗ dcfg-ve2dx — dispatch: временный файл pre-push не удаляется

Разведка — repowise: `repowise context git-hooks/dispatch --path /root/workspaces/tools` (53 строки, без символов).
Паспорт источников: `git-hooks/dispatch:28-29` — `tmp=$(mktemp)` и `trap 'rm -f "$tmp"' EXIT HUP INT TERM`; строки `:39` и `:47` — `exec "$hook" "$@" < "$tmp"`. `exec` заменяет процесс оболочки, ловушка EXIT не выполняется → файл остаётся в `/tmp` на каждый push (bd dcfg-ve2dx).

Только два файла этого worktree. Пробы и скрипты вне worktree не создавать.

## U1 — `git-hooks/dispatch`
В строках `:39` и `:47` (вызов с `< "$tmp"`) убрать `exec`: `"$hook" "$@" < "$tmp"` и следом `exit $?`. Строки `:41` и `:49` (без `$tmp`) не менять. Другой код не менять.

## U2 — `bin/secret-gate-test`, новая проверка перед итоговой строкой `echo "PASS $PASS FAIL $FAIL"`
По образцу проверки `(ф)` (копия dispatch в `$SANDBOX/hooks/pre-push`, строка `:218`): задать `TMPDIR` = отдельный пустой каталог в `$SANDBOX`, положить цепочечный хук, который сам выходит с 0, выполнить pre-push → после выхода каталог `TMPDIR` пуст. Пусто → `PASS=$((PASS+1))`, иначе `FAIL=$((FAIL+1)); echo "FAIL[dispatch-tmp]"`. Сначала добавить проверку и увидеть `FAIL[dispatch-tmp]`, затем U1. Прежние проверки не менять.

Не коммитить. Проверка (один прогон): `bin/secret-gate-test` → `FAIL 0`.

## v2 — причина: прогон 1 исправил только `:47`, `:39` остался `exec`; проверка `(щ)` ложная
Хук `$SANDBOX/hooks/pre-push-chain` dispatch не вызывает: он ищет `$(git rev-parse --git-common-dir)/hooks/pre-push` (`dispatch:36`). Проверка проходит и без фикса.
1. Проверка `(щ)`: цепочечный хук `exit 0` положить ровно в `$(git -C <репо песочницы> rev-parse --git-common-dir)/hooks/pre-push` того репо, из которого идёт push. Код выхода push проверять: не 0 → `FAIL[dispatch-tmp] push rc=…`.
2. Временно вернуть `exec` в `:47`, запустить `bin/secret-gate-test` и увидеть `FAIL[dispatch-tmp]`. Затем исправить `:39` и `:47` (`"$hook" "$@" < "$tmp"` и следом `exit $?`, отступ как у соседних строк) → `FAIL 0`.
