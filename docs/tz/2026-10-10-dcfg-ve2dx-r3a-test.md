# ТЗ dcfg-ve2dx r3a — проверка (щ) через настоящий путь хука

Остаток после прогонов 1–2 (FR-021, FR-030). Разведка — repowise: `repowise context git-hooks/dispatch --path /root/workspaces/tools`.
Факт после прогона 2: проверка `(щ)` в `bin/secret-gate-test` кладёт хук в `$SANDBOX/hooks/pre-push-chain`; `git-hooks/dispatch:36` ищет `$(git rev-parse --git-common-dir)/hooks/pre-push` — хук не вызывается, проверка проходит без фикса.

Только файл `bin/secret-gate-test` этого worktree. `git-hooks/dispatch` не менять.

## U1
В проверке `(щ)`: цепочечный хук (`#!/bin/sh` + `exit 0`, chmod 700) положить в `$(git -C <репо, из которого идёт push> rev-parse --git-common-dir)/hooks/pre-push`. Код выхода push сохранить; push rc ≠ 0 → `FAIL=$((FAIL+1)); echo "FAIL[dispatch-tmp] push rc=$rc"`. Остальное в проверке не менять.

Проверка (один прогон): `bin/secret-gate-test` → строка `FAIL[dispatch-tmp]` (ожидаемо: `dispatch:39` ещё `exec`).
