# ТЗ dcfg-po0b4 — требование разведки через индекс в промпте исполнителя

Разведка — repowise: `repowise symbol "bin/code-channel::run_form" --path /root/workspaces/tools`.
Паспорт источников: в run_form `bin/code-channel` прямо перед `if [[ $id == codex ]]; then` стоят три строки-префикса `prompt=$(printf '…\n\n%s' "$prompt")` для всех форм (после dcfg-tdd86.3, e4cce6d); `grep -n repowise bin/code-channel` → 0 строк. Слово владельца 09.10 (bd dcfg-po0b4): исполнители работают через кодовую базу repowise/codebase-memory без исключения.

## U1 — `bin/code-channel`
Сразу после этих трёх строк добавить четвёртую того же вида:
`prompt=$(printf 'Разведка кода — только через индекс: repowise (repowise context|symbol|risk <путь> --path <корень репо>) и codebase-memory; файл кода читай только перед его правкой\n\n%s' "$prompt")`
Другой код не менять.

## U2 — `bin/code-channel-test`, проверки 42 и 43 в конце
42) Форма go (конфиг `$go`), заглушка opencode rc 0 → `$log` аргументов содержит `только через индекс: repowise`.
43) Форма codex (конфиг одной ступени codex, как в существующих проверках codex) → записанные аргументы codex содержат ту же строку.
Проверки 1–41 не менять; итог — `PASS 43/43`.

Не коммитить. Проверка (один прогон): `bin/code-channel-test` → `PASS 43/43`, FAIL нет.
