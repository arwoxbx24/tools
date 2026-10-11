# ТЗ dcfg-ac946.2 — канал кода: модель audit из конфига, id сессии в журнале

Атом: dcfg-ac946.2. Worktree: `/root/workspaces/tools/.worktrees/claude/dcfg-ac946`. Правка только `bin/code-channel` и `bin/code-channel-test`.
Паспорт источников: `bin/code-channel:9` (схема конфига jq), `:11` (`--plan`), `:83-88` (чтение модели и `--model`), `:90-98` (`write_journal`), `:111-119` (`reconcile`); `bin/code-channel-test:107` (check 22), `:137-146` (стабы `SQLITE_SESSION_ID`, `OPENCODE_SEQUENCE`), `:183` (итог). Конфиг `config/code-channel.json` уже содержит у `go` новое поле `audit_model` — его не трогать.

## U1. Модель по режиму (`bin/code-channel`)
1. `:9` — схема: добавить необязательное строковое поле `audit_model` по образцу `resume_model`.
2. `:83` — читать `audit_model` вместе с остальными полями.
3. После `model=${override:-$model}` (`:88`): если `mode == audit`, `--model` не задан и `audit_model` не пуст → `model=$audit_model`.
4. `:84` — `--model` допустим, если равен `model`, `resume_model` или `audit_model`; иначе прежний rc 3 «модель не в конфиге».
5. `:11` `--plan`: строка ступени — как сейчас; если `audit_model` не пуст, в конец строки через пробел `audit=<audit_model>`.

## U2. Итог прогона не теряется (`bin/code-channel`)
1. `reconcile` (форма не codex): найти id сессии `select id from session where title='$id_run' order by time_created desc limit 1` (тот же запрос, что `:264`) и передать в `write_journal`.
2. `write_journal`: новое поле `session` (строка, у codex пустая). Остальные поля и порядок rc не менять.
3. Таймауты 290/590, resume и выход по 124 (spec:035 FR-026) не менять.
4. Дефект `:271-273`: при `run` ≠ 0 и успешной сверке канал выходит с rc 0 (факт 11.10: `run=1`, «unknown field promptCacheKey», rc 0, отчёт пустой). Исправить: сверка прошла (rc 0), а `run` ≠ 0 → выход с `run` (124 — как сейчас). Тогда лестница переходит на следующую ступень по прежним правилам.

## U3. Тесты (`bin/code-channel-test`)
1. check 22: ожидаемый вывод `--plan` по боевому конфигу:
   `go opencode-go/glm-5.3-flash - audit=opencode-go/longcat-2.5-preview-free` и вторая строка `codex - high`.
2. Новый конфиг-стаб: `go` с `model` `opencode-go/mimo-v2.6-flash` и `audit_model` `opencode-go/audit-free`.
3. check 49: `audit` с этим конфигом → rc 0, в логе `--agent audit` и `-m opencode-go/audit-free`.
4. check 50: `go` (code) с этим конфигом → rc 0, в логе `-m opencode-go/mimo-v2.6-flash`, нет `audit-free`.
5. check 51: конфиг `$go`, `OPENCODE_RC=124 SQLITE_SESSION_ID=session-123` → rc 124 и в `$runs` есть `"session":"session-123"`.
6. check 52: `go --model opencode-go/audit-free` с конфигом из п.2 → не rc 3.
7. check 53: конфиг `$gocodex`, `OPENCODE_RC=1 SQLITE_RESULT='opencode-go|mimo-v2.6-flash'`, `auto` → в логе есть строка `codex ` (переход на codex), в stderr `switch go→codex rc=1`.
8. Итог: `[[ $ok == 53 ]] && echo 'PASS 53/53'`.

## Запреты
Не трогать: таймауты, resume, коды выхода, лестницу, конфиг, другие файлы. Без новых зависимостей. KISS, YAGNI.

## Готово, когда
1. `bash bin/code-channel-test` → последняя строка `PASS 53/53`.
2. `bash -n bin/code-channel` rc 0.
3. `git diff --stat` — только `bin/code-channel`, `bin/code-channel-test`.
