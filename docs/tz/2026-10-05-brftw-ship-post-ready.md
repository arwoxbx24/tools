# ТЗ dcfg-brftw — ship-post: готов только закрытый атом без слитого PR (атом dcfg-brftw, эпик dcfg-6v0u2)

## U1
Два файла: bin/ship-post, bin/ship-post-test. Разведка — repowise, затем `grep -n`. Новых файлов нет.

Факт (`ship-post --dry-run`, 05.10): ready 13; после squash-merge HEAD ветки не предок origin/main → повторная отгрузка; атомы open/in_progress тоже ready.

1. bin/ship-post, после проверки `merge-base --is-ancestor` (строки 54-58), два новых skip в той же форме (`[[ $dry_run == 1 ]] && echo "skip $wt <причина>"`, `skip=$((skip + 1))`, `continue`):
   - атом не закрыт: `st=$(bd show "$atom" --json 2>/dev/null | jq -r '.[0].status' 2>/dev/null)`; `[[ $st != closed ]]` → причина `атом не закрыт ($st)`.
   - PR слит: `br=$(git -C "$wt" branch --show-current)`; `head=$(git -C "$wt" rev-parse HEAD)`; `(cd "$wt" && gh pr list -H "$br" -s merged --json headRefOid -q '.[].headRefOid' 2>/dev/null) | grep -qx "$head"` → причина `PR слит`.
2. bin/ship-post:78 — `bd create … | tail -1` даёт строку статуса, не id. Заменить `| tail -1` на флаг `--silent` (вывод только id).
3. bin/ship-post-test: заглушки `bd` и `gh` в PATH теста (форма — как существующие заглушки, если есть; иначе функция-скрипт в `$d/bin`). Сценарий: worktree с трейлерами, атом `open` → skip `атом не закрыт`; атом `closed`, gh отдаёт HEAD → skip `PR слит`. Старые сценарии: заглушка bd отдаёт `closed`, gh — пусто.

Паспорт: `gh pr list --help` (вывод 05.10): «-H, --head string Filter by head branch», «-s, --state string Filter by state: {open|closed|merged|all}», JSON-поле `headRefOid`, «-q, --jq expression». `bd create --help` (bd 1.3.0): «--silent Output only the issue ID (for scripting)». `bd show <id> --json | jq -r '.[0].status'` → `closed` (замер 05.10).

Тест один раз: `bin/ship-post-test` → FAIL нет, код 0. Проверка: `bash -n bin/ship-post` → 0; `grep -c 'tail -1' bin/ship-post` → 0 в строке bd create.

## U2 (ТЗ v2 — причина: после U1 `--dry-run` даёт ready 5 — старые ветки закрытых атомов до почтальона, PR по ним не слит)
Один файл bin/ship-post, одна проверка сразу после проверки трейлеров ТЗ/Atom, та же форма skip:
`(( $(git -C "$wt" log -1 --format=%ct) < ${SHIP_POST_SINCE:-1791205200} ))` → причина `ветка старше почтальона`.
Комментарий над строкой: `# ponytail: отсечка 2026-10-05T13:00Z — ветки до почтальона отгружает их владелец; убрать, когда старых worktree не останется`.
ship-post-test не менять: тестовые коммиты новее отсечки.
Проверка: `bash -n bin/ship-post` → 0; `bin/ship-post-test` → FAIL нет, код 0.
