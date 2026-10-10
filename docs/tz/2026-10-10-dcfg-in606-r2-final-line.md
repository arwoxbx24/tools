# ТЗ dcfg-in606 r2 — проверка модели в итоговой строке

Остаток после прогона 1 (FR-021, FR-030). Разведка — repowise: `repowise symbol "bin/code-channel::run_form" --path /root/workspaces/tools`.
Факт после прогона 1: проверка была ложной — строка продолжения `resume session=%s model=%s` печатает модель и без правки, `grep model=…` проходил на старом коде. Worktree переведён на main 6f78bfc (сторож FR-033), правки прогона 1 сняты.

Только `bin/code-channel` и `bin/code-channel-test` этого worktree. Пробы не создавать — сразу правка.

## U0 — `bin/code-channel`
1. Итоговая строка (`:138`, `printf 'code-channel: mode=%s form=%s provider=%s precheck=%s …`): после `provider=%s` добавить `model=%s`, значение `$model`.
2. Перед вызовом продолжения `run_guarded 290 opencode run --session …` присвоить `model=$resume_model`.
Другой код не менять.

## U1
Сначала U1 (проверка), прогнать тест → FAIL новой проверки; затем U0 → PASS.
1. Проверка модели сверяет именно итоговую строку: `grep -Eq '^code-channel: mode=code .* model=opencode-go/mimo-v2.6-flash precheck=' "$tmp/err"`. Номер проверки — следующий после последней в файле; итоговая строка `PASS N/N` — под новое N.
2. В отчёт — rc канала при заглушке `OPENCODE_SEQUENCE=124,0` дословно из вывода.

Проверка (один прогон): `bin/code-channel-test` → `PASS N/N`, FAIL нет.
