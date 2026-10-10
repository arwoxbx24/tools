# ТЗ — repowise для цепочки ship в tools: индекс git-auto-lib + MCP в opencode (spec:099 v6, разрешение владельца 10.10)

## U1
Владелец 10.10: «без repowise работа запрещена»; «разрешаю подключить кодовую базу… произвести актуализацию кодовой базы repowise».

Факты (замер главного агента 10.10):
- `repowise update --index-only --no-workspace /root/workspaces/tools` → rc 0; MCP `get_context`: `indexed_commit a1513744eb06 == live_head`, `index_behind:false`.
- `bin/git-auto-lib` → `index_status: live_file_without_index_record`, `no indexed symbols`. Первая строка файла — комментарий, без `#!`; у `bin/ship-post` первая строка `#!/usr/bin/env bash` и символы есть.
- opencode: `opencode mcp list` → `repowise disabled`. Глобально выключен нарочно (spec:082, `~/.config/opencode/opencode.jsonc:69-70`: «включаются opencode.json в корне проекта»). Документация https://opencode.ai/docs/config/: «it first looks for a config file in the current directory, then traverses up to the nearest Git directory» — значит файл нужен в репо, чтобы попасть в каждый worktree.

Правка (атом ≤10 строк):
1. `bin/git-auto-lib`: вставить первой строкой `#!/usr/bin/env bash`. Больше ничего в файле. Файл подключается через `source` — строка `#!` при этом комментарий, поведение не меняется.
2. `opencode.json` в корне репо (пишет главный агент): MCP `repowise` с путём `/root/workspaces/tools`, образец `projects/kint-b24/opencode.json`.
3. `docs/ship-post-ARCHITECTURE.md` §6: одна строка — `bin/git-auto-lib` начинается с `#!/usr/bin/env bash`, чтобы repowise индексировал функции `ga_*`.

Разведка — ПЕРВЫМ repowise: `/root/.local/bin/repowise context bin/git-auto-lib --path /root/workspaces/tools --format json`.

Критерии:
1. `head -1 bin/git-auto-lib` → `#!/usr/bin/env bash`; `bash -n bin/git-auto-lib` → rc 0.
2. `bash bin/ship-doc-check origin/main` → rc 0.
3. `git diff --stat` → только 3 файла выше.
Тесты не запускать — их прогонит CI.
Запреты: другие файлы, git commit/push (коммитит главный агент), сеть.
