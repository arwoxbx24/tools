# ТЗ dcfg-vzy6r — ship-post: bd close от точного assignee атома (Claude ≡ Claude Code ≡ claude)

## U1 — актор закрытия = assignee атома
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

Причина (замер 09.10): `ship-post --submit` с `BEADS_ACTOR=Claude` закоммитил `dcfg-co7v4` и упал: `bd close failed (exit 1): cannot close dcfg-co7v4: assignee is "Claude Code", actor is "Claude"`. `bin/ship-post:117` и `:126` считают `Claude`, `Claude Code`, `claude` одним агентом, а `bd_cmd close` (`:210`) передаёт сырой `BEADS_ACTOR`; bd 1.3.0 сверяет assignee и actor буквально. Актор bd по умолчанию — `$BEADS_ACTOR`, затем `git user.name`, затем `$USER` (`bd --help`, флаг `--actor`), поэтому имя assignee зависит от того, кто и где брал атом. Тот же разрыв с `BEADS_ACTOR=claude` → `unknown BEADS_ACTOR` (`:117`).

Решение (ADR): правка только в `do_submit` файла `bin/ship-post`.
1. `:117` — `case` принимает и нижний регистр: `Codex|codex) caller=codex`, `Claude|'Claude Code'|claude) caller=claude`.
2. `:125-127` — сохранить сырое значение assignee из `bd show` в отдельную переменную до нормализации. После успешной проверки семьи (`$assignee == $caller`) выполнить `BEADS_ACTOR=$<сырое assignee>` — дальше `bd_cmd close` идёт от точного имени владельца атома.
3. Режим `--watch`, `actor_name`, `ship` — не менять.

Тест — `bin/ship-post-test`: новая функция `test_actor_alias`, вызвать в общем списке тестов в конце файла. Номера проверок — свободные (≥100, `grep -n 'local n=' bin/ship-post-test`), чтобы не попасть в `case $n` строк 14-18.
- A1: `BEADS_ACTOR=Claude`, `BD_ASSIGNEE='Claude Code'`, ветка `claude/dcfg-alias.1` → rc 0; в `$d/bd.calls` строка `$d|Claude Code|close dcfg-alias.1 --reason submitted <HEAD>: evidence`.
- A2: `BEADS_ACTOR=Claude`, `BD_ASSIGNEE=claude` → rc 0; close от актора `claude`.
- A3: `BEADS_ACTOR=claude`, `BD_ASSIGNEE='Claude Code'` → rc 0; close от `Claude Code`.
- A4: `BEADS_ACTOR=codex`, `BD_ASSIGNEE=Codex`, ветка `codex/…` → rc 0; close от `Codex`.
- Существующие проверки не менять и не ослаблять; проверка `wrongactor` (`Codex` против `Claude Code`) обязана остаться ненулевой.

Запреты: только `bin/ship-post` и `bin/ship-post-test`; без `--force` и обхода сверки bd; без новых зависимостей; `rm -rf` запрещён; соседний код не чистить. Принципы: KISS, YAGNI, fail fast.

Критерии:
1. `bash -n bin/ship-post` rc 0.
2. `bin/ship-post-test` → `failures=0`, rc 0, в выводе PASS проверок A1–A4.
3. `grep -c 'BEADS_ACTOR=' bin/ship-post` вырос на 1 относительно `origin/main`.

Паспорт источников: `bin/ship-post:10,67,117,121-127,209-214,222-224`; `bin/ship-post-test:52-94,108-120,128`; `bd --help` (bd 1.3.0): `--actor string  Actor name for audit trail (default: $BEADS_ACTOR, git user.name, $USER)`.
