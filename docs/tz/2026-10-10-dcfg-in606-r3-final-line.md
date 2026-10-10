# ТЗ dcfg-in606 r3 — модель в итоговой строке канала

Остаток r2 (FR-030): r2 оборван сторожем FR-033 (откатан #221), правок 0. Worktree на main 480c320.
Разведка — repowise: `repowise symbol "bin/code-channel::run_form" --path /root/workspaces/tools`.

Только `bin/code-channel` и `bin/code-channel-test` этого worktree. Пробы не создавать — сразу правка.

## U1 — сначала проверка (red)
`bin/code-channel-test`: новая проверка 46 в конце: `CC_CONFIG=$go`, заглушка opencode rc 0, `SQLITE_RESULT='opencode-go|mimo-v2.6-flash'`; условие — `grep -Eq '^code-channel: mode=code .* model=opencode-go/mimo-v2.6-flash precheck=' "$tmp/err"`. Итог `PASS 46/46` (было `:170` `PASS 45/45`). Прогнать → FAIL 46.

## U0 — `bin/code-channel`
1. `:107` printf итоговой строки: после `provider=%s` добавить ` model=%s`, значение `"$model"`.
2. Перед `:241` (`timeout 290 opencode run --session …`) присвоить `model=$resume_model`.
Другой код не менять.

Проверка (один прогон): `bin/code-channel-test` → `PASS 46/46`. В отчёт — строку FAIL red-прогона дословно.
