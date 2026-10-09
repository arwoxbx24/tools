# ТЗ dcfg-e3kyr — единая архитектурная дока ship-post + CI-гейт её актуальности + ship-test только при правке цепочки

## U1 — дока, гейт, CI
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.

Причина: архитектура цепочки доставки (`bin/ship-post`, `bin/ship`, `bin/git-sync`, `bin/git-auto-lib`, `bin/git-state`) описана в 10+ файлах spec 099 и в законах, причём противоречиво. В `TOOLS-REGISTRY.md` о `ship` нет ни строки (`grep -c ship` = 0). Новый агент не может быстро понять, что править. CI на каждом PR гоняет `bin/ship-test`: 218 с из 231 с всего job.

1. Файл `docs/ship-post-ARCHITECTURE.md`. Писать только по текущему коду, ничего не выдумывать. Разделы:
   1) цель и контракт агента: `ship-post --submit` для Claude и Codex, аргументы, отказы;
   2) C4-схема текстом: агент → ship-post (`--submit`/`--watch`, pm2 `ship-post`, `ecosystem.config.js`) → bd events → ship `--handover` → GitHub PR/CI/merge → git-sync → основные папки;
   3) последовательность одной доставки — якоря строго в формате `` `bin/<файл>:<функция>` ``;
   4) состояние: `state/ship-post/{submissions,receipts,inflight,locks}`, `cursor.json`, `refs/delivered`, `refs/rescue`;
   5) таблица кодов выхода ship (10/20/30/40/50/60/70/…) и ship-post (21-24); какие из них временные;
   6) режимы отказа и восстановление: конфликт (50), смена SHA, нет CI, репо со skip-причиной;
   7) наблюдаемость: pm2-логи, `*.log` у квитанций, bd-заметки, `git-state`;
   8) переменные окружения и жёстко прописанные пути (для переноса программы);
   9) тесты и CI;
   10) ссылки: spec 099, `LAWS-PROCEDURES.md` §«Ветки агентов».
2. `bin/ship-doc-check [<base-ref>]`, по умолчанию `origin/main`:
   - (а) `git diff --name-only <base>...HEAD` задевает `^bin/(ship|ship-post|git-sync|git-auto-lib|git-state)$`, а `docs/ship-post-ARCHITECTURE.md` не изменён → `echo 'ship-doc-check: цепочка изменена без docs/ship-post-ARCHITECTURE.md' >&2; exit 1`;
   - (б) каждый якорь `` `bin/X:fn` `` из доки: файл есть и `grep -qE "^(function )?fn\(\)" bin/X`; иначе — имя якоря в stderr и `exit 1`;
   - иначе `exit 0`.
3. `bin/ship-doc-check-test` во временном репо: правка `bin/ship-post` без доки → rc 1; с правкой доки → rc 0; битый якорь → rc 1; правка постороннего файла → rc 0.
4. `.github/workflows/tools-smoke.yml`:
   - `actions/checkout@v4` с `fetch-depth: 0`;
   - шаги `bash bin/ship-doc-check "origin/${{ github.base_ref || 'main' }}"` (только на pull_request) и `bash bin/ship-doc-check-test`;
   - шаг `bash bin/ship-test`: на pull_request — только если `git diff --name-only origin/${{ github.base_ref }}...HEAD` задевает `^bin/(ship|ship-post|git-sync|git-auto-lib|git-state)|^bin/ship-test`; на push в main — всегда;
   - workflow не отключать фильтром `paths:`: `ga_ci_wait` ждёт появления прогона на pull_request (`bin/git-auto-lib:129-136`).
5. `TOOLS-REGISTRY.md`: одна строка-указатель на `docs/ship-post-ARCHITECTURE.md` в разделе инструментов. Формат строки — как у соседних.

Запреты: только названные файлы; не менять код `bin/ship*`, `git-sync`, `git-auto-lib`; без `rm -rf`, `--force`. Принципы: KISS, YAGNI.

Критерии:
1. `bash bin/ship-doc-check origin/main` в ветке → rc 0.
2. `bash bin/ship-doc-check-test` → rc 0.
3. PR этого атома: CI tools-smoke SUCCESS.

Паспорт: `bin/ship-post`, `bin/ship`, `bin/git-auto-lib:121-193`, `bin/git-sync`, `ecosystem.config.js` (процесс `ship-post`), `.github/workflows/tools-smoke.yml`, `/root/workspaces/projects/specs/099-ship-dev-prod/`.
