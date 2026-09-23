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
| `tools/bin/pm2-boot` | загрузка/перезапуск процессов PM2 fail-closed (spec:025) | `pm2-boot <имя>` | Claude, Codex | штатно |
| `tools/bin/pm2-boot-test`, `pm2-chaos`, `pm2-loop-guard`, `pm2-loop-guard-test`, `pm2-eco-lint` | тесты/страж PM2 (spec:025) | по имени | Claude, Codex | штатно |
| `tools/bin/restic` | бэкапы (spec backup-coverage) | `restic …` через скрипты `tools/scripts/` | Codex | штатно |
| `tools/bin/share-test` | самотест share | `share-test` | Claude | штатно |
| `pm2` | управление процессами — только `startOrReload <ecosystem> --only <имя>` → `pm2 save` | см. `/root/CLAUDE.md` PM2 | все | штатно |
| `tools/scripts/pm2/b244-fetch.sh` | загрузка файлов b244/MinIO | `bash …/b244-fetch.sh <b244://…>` | все | штатно |
| `tmux send-keys` | сообщение другому агенту: `-l "<текст>"` → отдельный `Enter` → `capture-pane` | см. `/root/CLAUDE.md` tmux | Claude ↔ Codex | штатно |
| `repowise` (MCP) | разведка кода первой ступенью | `get_answer/search_codebase/get_context` | Claude | штатно |
| `jq`, `grep`, `wc`, `ls`, `git`, `gh` | чтение, замеры, git-слой (I11) | одна команда на вызов | все | штатно |
| `python3 <файл из tools/ или проекта>` | штатные скрипты (`layout_check.py`, `deploy_manifest.py`, тесты проектов) | путь к файлу, без `-c` | все | штатно |
| `Workflow name=audit|verify|bd-slice|code-atom` | делегирование (csb стадия 7) | по имени, args `{atom,path,tz}` | Claude | штатно |
| `transcribe` (`tools/bin/transcribe`) | ЕДИНСТВЕННАЯ транскрибация аудио/видео (spec:056 → spec:059, 23.09): AssemblyAI первым (целиком до 10 ч, спикеры, SRT/VTT), запасной Groq `whisper-large-v3`; файл, прямая ссылка, страница YouTube и др. (`yt-dlp` в `.venv`); журнал `state/transcribe/runs.jsonl`; из любой папки | `transcribe <файл\|ссылка> [--format txt\|srt\|vtt\|json] [--speakers] [--engine auto\|assemblyai\|groq] [--lang ru]`; навык `.claude/skills/transcribe` | все | штатно |
| `transcribe-test` | живой самотест транскрибации, итог `PASS 9/9` | `transcribe-test` | все | штатно |

## 3. ЗАПРЕЩЕНО (машинно: Claude — managed deny; opencode — `permission.bash "*": deny`; Codex — его hooks.json по вердикту)
| Форма | Почему | Замена |
|---|---|---|
| `python -c`, `python3 -c`, `python3 -`, heredoc `<<`, `bash -c`, `sh -c`, `zsh -c`, `node -e`, `perl -e`, `ruby -e`, `eval` | код мимо канала, TDD и ревью; 492 обхода/сутки (замер 18.09) | `opencode run` / `codex exec` |
| `claude -p`, `claude --print` | вложенная сессия сжигает лимит подписки | `Workflow` / `Agent` |
| `aider`, `or-run`, `tools/llm-providers/runner.sh`, `failover.sh` (OpenRouter-эра) | сняты владельцем; файлы оставлены без права исполнения (`chmod a-x`, 18.09) | `opencode run` |
| чтение/правка `~/.config/opencode/**` агентами | модель выбирает владелец | форма вызова из §1 |
| `pm2 start <файл>`, `pm2 delete`, `pm2 kill` | закон PM2 | `pm2-boot`, `startOrReload` |
| Любая транскрибация мимо `transcribe`: Yandex SpeechKit (`transcribe_yandex.py`, `run_yandex_transcribe.py`, `transcribe_with_iam.py`), `client-video-transcription/transcribe.py`, `run_groq_transcribe.py`, `transcription-dev/*`, `acc1-scripts/assemblyai-transcribe.py`, `acc1-scripts/groq-client.sh`, OpenAI/Gemini/OpenRouter-распознавание | запрет владельца 23.09 (SpeechKit — 31,70 ₽/нед), ключи OpenAI недействительны, Gemini — регион, путаница агентов | `transcribe` |

## 4. Замер (FR-007; окно 24 ч)
Базовая линия 18.09 10:00 (все транскрипты `~/.claude/projects` за 24 ч): `python -c` 224, `python3 -c` 160, `bash -c` 108, `claude -p` 6; `opencode run` 150, `codex exec` 148.
Команда: `grep -ohE '"command":"[^"]*(python3? -c |bash -c |sh -c |claude -p|claude --print)' $(find /root/.claude/projects -name '*.jsonl' -mmin -1440) | wc -l` → цель 0 (SC-001, атом dcfg-rzqfs.4).

## 5. Изменение реестра
Только владелец или главный агент по цели с `spec:<NNN>`; новая строка = коммит `agent-contour` + строка в `docs/csb-updates/<неделя>.md`. Дубли инструментов запрещены (закон двух папок).
