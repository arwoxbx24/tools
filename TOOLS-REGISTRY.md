# РЕЕСТР ИНСТРУМЕНТОВ АГЕНТОВ (spec:033, владелец 18.09) — закон для Claude, Codex, opencode

Один файл — один ответ «чем это делать». Инструмента нет в таблице → он запрещён. Модели и провайдеры выбирает только владелец
(`~/.config/opencode/opencode.jsonc` — для агентов Claude закрыт на чтение и запись managed-правилом).

## 1. Каналы кода и поиска данных (единственные)
| Инструмент | Назначение | Форма вызова (точно) | Кому | Статус |
|---|---|---|---|---|
| `opencode run` | весь исполняемый код, тесты, поиск по данным; модель зашита в конфиге (сейчас BitrixGPT через endpoint) | `cd <абс.путь проекта> && timeout 590 opencode run "<ТЗ>"` — только внутри агента workflow `code-atom` (главная сессия каналы не запускает, гейт R1) | Claude (workflow-агент), Codex | штатно |
| `codex exec` | резерв при отказе opencode (401, лимит, 124); самая дешёвая модель профиля | `timeout 590 codex exec -p quota-terra -s workspace-write "<ТЗ>"` из git-каталога, `-m` не задавать | Claude (workflow-агент) | штатно (резерв) |
| Ключ opencode | `VIBECODE_API_KEY` экспортируется из `secrets/projects/vibecode.env` в `/root/.bashrc` **до** guard интерактивности (18.09) | — | все оболочки | штатно |

## 2. Штатные инструменты контура
| Инструмент | Назначение | Форма | Кому | Статус |
|---|---|---|---|---|
| `bd` | единственный трекер (`ready/show/create/update --claim/close/remember`) | `bd <команда>`; в hh-scoring — `hh-scoring/.tools/bd` | все | штатно |
| `share` | короткая ссылка владельцу на файл (`b244.ru/<slug>`) | `share <файл>` | Claude, Codex | штатно |
| `where` (bin/where, dcfg-gl57f.2) | найти реальные пути конфигов/законов/трекера по ключу из `config/where.json` — вместо угадывания путей; `where --check` — проверить существование; `WHERE_FILE` — другой манифест | `where <слово>` (поиск по ключу, без слова — все ключи с заметкой); `where --check` | все | штатно |
| `route-hint` (bin/route-hint, dcfg-gl57f.2) | PostToolUseFailure hook: после обычного сбоя подсказывает маршрут из `routes.json` (только `kind=="failure"`, no match/сбой → без вывода, rc 0); `ROUTES_FILE` — файл правил | hook `./bin/route-hint` (stdin JSON → `additionalContext`) | Claude | штатно |
| `goal-guard` (bin/goal-guard, dcfg-gl57f.2) | Stop-hook страж десинк-ловушки: блокирует негативный статус без маршрутов, не даёт закрыть атомы; cap 8 блоков за сессию (`GOAL_GUARD_MAX`), в блоке пишет ближайшую `bd close`-команду | `bin/goal-guard` (stdin/stdout Claude hooks); самотест `bin/goal-guard-test` | Claude | штатно |
| `agent-errors-baseline` (bin/, dcfg-gl57f.2) | недельный замер ошибок агента против 4 целей владельца (bash_rate, denial_rate, path_errors, injected_chars); pm2-джоб `agent-errors-weekly` (пн 06:00) | `bin/agent-errors-baseline --days N --corpus DIR` (rc 0 всегда); самотест `bin/agent-errors-baseline-test` | оркестратор | штатно |
| `tools/bin/pm2-boot` | загрузка/перезапуск процессов PM2 fail-closed (spec:025) | `pm2-boot <имя>` | Claude, Codex | штатно |
| `tools/bin/pm2-boot-test`, `pm2-chaos`, `pm2-loop-guard`, `pm2-loop-guard-test`, `pm2-eco-lint` | тесты/страж PM2 (spec:025) | по имени | Claude, Codex | штатно |
| `tools/bin/restic` | бэкапы (spec backup-coverage) | `restic …` через скрипты `tools/scripts/` | Codex | штатно |
| `tools/bin/share-test` | самотест share | `share-test` | Claude | штатно |
| `tools/bin/sdk-agent` | the only Claude Agent SDK route (owner 16.10, dcfg-ghksc, renamed dcfg-sktr5); a paid API program, not a Claude Code agent or subagent: model claude-haiku-5-5, API key only in its process, budget ≤2.00 USD, log `sdk-agent/runs.jsonl`; run only when the owner mentions the SDK | `sdk-agent ask PROMPT`, `sdk-agent code WORKTREE TZ_FILE`; `--help`; test `bin/sdk-agent-test` | Claude, Codex | штатно |
| `tools/skill-search/` (`skills@1.5.18`, vercel-labs/skills, по lockfile) | штатный CLI поиска навыков skills.sh (spec:068; без обёрток — владелец 26.09 «только штатное») | `DISABLE_TELEMETRY=1 tools/skill-search/node_modules/.bin/skills find <слово>`; `add/use/update` не вызывать | все | штатно |
| `pm2` | управление процессами — только `startOrReload <ecosystem> --only <имя>` → `pm2 save` | см. `/root/CLAUDE.md` PM2 | все | штатно |
| `tools/scripts/pm2/b244-fetch.sh` | загрузка файлов b244/MinIO | `bash …/b244-fetch.sh <b244://…>` | все | штатно |
| `tools/bin/agent-browser` | CLI браузера vercel-labs/agent-browser@0.39.0 (локально в `tools/vendor/agent-browser`, обвязка bin/agent-browser: Playwright Chromium, демон гаснет после 10 с простоя; `--help` справка) | `tools/bin/agent-browser <command>` | все | штатно |
| `tmux send-keys` | сообщение другому агенту: `-l "<текст>"` → отдельный `Enter` → `capture-pane` | см. `/root/CLAUDE.md` tmux | Claude ↔ Codex | штатно |
| `tmux-send` | отправить текст другому агенту на изолированном сервере tmux; сервер выбирается через `TMUX_SEND_SOCKET` (`-L`, по умолчанию — текущий) | `TMUX_SEND_SOCKET=<сокет> bin/tmux-send <target> '<текст>' [--expect '<regex>']` | Claude ↔ Codex | штатно |
| `repowise` (MCP) | разведка кода первой ступенью | `get_answer/search_codebase/get_context` | Claude | штатно |
| `bin/ship-post` | доставка завершённых атомов: локальный submit и courier | [docs/ship-post-ARCHITECTURE.md](docs/ship-post-ARCHITECTURE.md) | Claude, Codex | штатно |
| `jq`, `grep`, `wc`, `ls`, `git`, `gh` | чтение, замеры, git-слой (I11) | одна команда на вызов | все | штатно |
| `python3 <файл из tools/ или проекта>` | штатные скрипты (`layout_check.py`, `deploy_manifest.py`, тесты проектов) | путь к файлу, без `-c` | все | штатно |
| `Workflow name=audit|verify|bd-slice|code-atom` | делегирование (csb стадия 7) | по имени, args `{atom,path,tz}` | Claude | штатно |
| `mise` (v2026.9.14, бинарь GitHub releases, SHA256 сверен) | тулчейн языка per-project без глобальных пакетов (Go, Java, .NET, Rust, Ruby…); `mise.toml` в проекте | `/root/.local/bin/mise use <tool>@<ver>` в каталоге проекта, запуск `mise exec -- <cmd>`; данные `~/.local/share/mise` (офиц. путь) | все (владелец 26.09) | штатно |
| `claude --settings /root/workspaces/tools/claude-sandbox-settings.json` | машинная стена теста в sandbox: deny Edit/git/pm2/gh/tmux/docker вне теста + deny Read чужих проектов, конституции, ecosystem (26.09: тест 1 закоммитил в ecosystem, тест 2 читал rss-tg-ins) | ПОРЯДОК: 1) `mkdir sandbox/test-<имя>` + `request.txt`; 2) окно `tmux new-window -d -t cl: -n test-<имя> -c <каталог>`; 3) `claude --settings <этот файл> "<запрос>"`; 4) наблюдение, стоп по бюджету csb — Escape; 5) выход `/exit`; 6) результат в bd; 7) удаление каталога и окна — по закону «Тестовый мусор». ЗАПРЕТЫ стены: путь конкретного теста в файл не вписывать (Read deny = и запрет записи: тест 2 не смог писать план); штатный `sandbox.enabled` Claude Code на этом сервере не включать — AppArmor `apparmor_restrict_unprivileged_userns=1` роняет каждую команду (тест 3), починка = правка /etc только по слову владельца | все (владелец 26.09) | штатно |
| `copier` (9.18.2) | каркас проекта из готового шаблона по answers-файлу; обновление проекта | `/root/workspaces/tools/copier-venv/bin/copier copy --defaults <шаблон> <каталог>`, `… update` | все (владелец 26.09) | штатно |
| ASSERT (`assert-ai` 0.3.0, responsibleai) | проверка ИИ-бота на уязвимости: взлом текстом (prompt injection), несанкционированные действия плагинов, помощь во взломе, утечка данных о людях и между пользователями, выдумывание фактов; испытан 04.10 на telegram-ai-bot (спека, отчёт, 9 конфигов — `projects/telegram-ai-bot/evals/assert/`, dcfg-d3qnd) | `/root/workspaces/sandbox/test-assert/.venv/bin/assert-ai estimate <конфиг>` — оценка токенов без вызова провайдера; прогон теста платный — только словом владельца после названной цены; установка в `sandbox/test-assert` (тестовая папка — не удалять, пока строка в реестре) | Claude (оркестратор), запуск — через субагента/Workflow | проба 04.10; судья gpt-4o-mini завышает вред — пометки сверять вручную |

## 3. ЗАПРЕЩЕНО (машинно: Claude — managed deny; opencode — `permission.bash "*": deny`; Codex — его hooks.json по вердикту)
| Форма | Почему | Замена |
|---|---|---|
| `python -c`, `python3 -c`, `python3 -`, heredoc `<<`, `bash -c`, `sh -c`, `zsh -c`, `node -e`, `perl -e`, `ruby -e`, `eval` | код мимо канала, TDD и ревью; 492 обхода/сутки (замер 18.09) | `opencode run` / `codex exec` |
| `claude -p`, `claude --print` | вложенная сессия сжигает лимит подписки | `Workflow` / `Agent` |
| `aider`, `or-run`, `tools/llm-providers/runner.sh`, `failover.sh` (OpenRouter-эра) | сняты владельцем; файлы оставлены без права исполнения (`chmod a-x`, 18.09) | `opencode run` |
| чтение/правка `~/.config/opencode/**` агентами | модель выбирает владелец | форма вызова из §1 |
| `pm2 start <файл>`, `pm2 delete`, `pm2 kill` | закон PM2 | `pm2-boot`, `startOrReload` |

## 4. Замер (FR-007; окно 24 ч)
Базовая линия 18.09 10:00 (все транскрипты `~/.claude/projects` за 24 ч): `python -c` 224, `python3 -c` 160, `bash -c` 108, `claude -p` 6; `opencode run` 150, `codex exec` 148.
Команда: `grep -ohE '"command":"[^"]*(python3? -c |bash -c |sh -c |claude -p|claude --print)' $(find /root/.claude/projects -name '*.jsonl' -mmin -1440) | wc -l` → цель 0 (SC-001, атом dcfg-rzqfs.4).

## 5. Изменение реестра
Только владелец или главный агент по цели с `spec:<NNN>`; новая строка = коммит `agent-contour` + строка в `docs/csb-updates/<неделя>.md`. Дубли инструментов запрещены (закон двух папок).
