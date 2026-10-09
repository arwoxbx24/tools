# ТЗ dcfg-bjch1 — повторяющиеся ошибки доставки: один корень — одна правка (владелец 09.10)

Исполнитель пишет код сам, code-channel не вызывает. Разведка — repowise (индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`); читать только указанные строки. Секреты, .env, auth.json, ~/.codex/*.toml, ~/.ssh не читать. pm2, сеть, git commit/push не вызывать — коммит делает ship. KISS: три точечные правки, больше ничего.

## Факты (замер 09.10, главный агент)
- `bin/ship:173,175,176` — `bd show/update/close` без указания базы; из вложенного репо (`projects/arwox-v3-src` со своей `.git`) bd пишет `no beads database found` → `ship: закрой вручную`, `post_rc=60` (`:177-178`) при уже смёрженном PR (PR #13 arwox-v3-src).
- `BEADS_DIR=/root/workspaces/projects/.beads bd where` → `/root/workspaces/projects/.beads` (проверено).
- `bin/ship-post:46` — список `/root/workspaces/projects:/root/workspaces/tools`; `:110-111` — точное сравнение с git-common-dir → вложенный репо: `repository is not served by courier`.
- `projects/.claude/workflows/code-atom.js` — промпт исполнителю не запрещает коммит; песочница исполнителя держит `.git` read-only → `index.lock: Read-only file system`, ходы впустую. Коммит по устройству делает ship (`bin/ship:81-91`).

## U1. `bin/ship` — в начале скрипта (после `set` и до первого вызова bd) одна строка:
`export BEADS_DIR=${BEADS_DIR:-/root/workspaces/projects/.beads}`

## U2. `bin/ship-post:110` — репо разрешён, если его realpath равен кандидату ИЛИ лежит внутри него (`"$cand"/*`). Остальную логику не менять.

## U3. `/root/workspaces/projects/.claude/workflows/code-atom.js` — в текст промпта исполнителю одна фраза: «git add/commit/push не выполнять: коммит делает ship/ship-post. Конец работы — изменённые файлы в рабочей копии и вывод тестов ТЗ.»

## Критерии
1. `bash -n bin/ship bin/ship-post` rc 0; `node --check` для code-atom.js rc 0 (если node есть).
2. `grep -n BEADS_DIR bin/ship` → 1 строка до первого `bd `.
3. `git diff --stat` — только эти файлы и ТЗ.

## Паспорт источников
- `bd --help`: флаг `-C`, сообщение bd «set BEADS_DIR to point to your .beads directory» (вывод 09.10).
- grep ship:173-178, ship-post:46,111 — 09.10; разбор субагента sonnet (данные, проверены grep).
