# ТЗ dcfg-9so4t — safe-delete v2 (спека projects/specs/007-fix-delete-gate/spec.md §v2)

СЕЙЧАС ВЫПОЛНЯТЬ ТОЛЬКО РАЗДЕЛ: U4 (U1–U3a сделаны и закоммичены). Остальные разделы — не трогать.
ВНИМАНИЕ ИСПОЛНИТЕЛЮ: ты уже запущен внутри `code-channel`. Правь файлы сам. `code-channel`, `opencode run`, `codex exec` НЕ вызывать. git commit не делать — коммитит оркестратор.
Разведка — repowise; индекс: repowise/CBM проверен, нет — `tools/bin/code-memory-enable`.
Файлы (только эти): `bin/safe-delete`, `bin/safe-delete-test`. Стиль файла сохранить (bash, `refuse`, `log` 8 колонок). Принципы: SOLID, DRY, KISS, YAGNI, fail fast; без чистки соседнего кода; ≤100 новых строк на раздел.
Запуск тестов: `bash bin/safe-delete-test` (все прежние PASS, сейчас T1–T33, обязаны остаться PASS).

Паспорт источников:
- git hash-object: https://git-scm.com/docs/git-hash-object — «--no-filters: Hash the contents as is, ignoring any input filter that would have been chosen by the attributes mechanism».
- git rev-parse `<rev>:<path>`: https://git-scm.com/docs/gitrevisions — «<rev>:<path>… names the blob or tree at the given path in the tree-ish object».
- git update-ref: https://git-scm.com/docs/git-update-ref — создаёт ссылку, объект недоступен для gc, пока на него есть ref.
- git ls-files -v: https://git-scm.com/docs/git-ls-files — «-v: Similar to -t, but use lowercase letters for files that are marked as assume unchanged»; «S» — skip-worktree.

## U1 — git-путь, строка вывода, restore (атом dcfg-9so4t.1; FR-201, FR-205, FR-206)
В режиме `file`, после прежних проверок пути и до копирования, для каждого файла:
1. git-путь применяется, только если ВСЕ условия: файл внутри git-репо (`git -C <dir> rev-parse --show-toplevel`); отслеживается (`git ls-files --error-unmatch`); не symlink (`[[ ! -L ]]`); строка `git ls-files -s` — режим `100644` или `100755` (не 120000/160000); `git ls-files -v` — первая буква `H` (не `h`/`S`); `git check-attr filter -- <путь>` не содержит `lfs`; `git hash-object --no-filters <файл>` == `git rev-parse HEAD:<относительный путь>`.
2. Тогда: `git update-ref refs/safe-delete/<ts>-<blob12> <blob>` (ts = `date +%Y%m%d%H%M%S%N`), удалить файл, `log git "<путь>" "<blob>" "<repo>" "refs/safe-delete/<ts>-<blob12>" "-" "-"` (колонки дополнить до 8 так, как делают соседние вызовы `log`). Копия не делается.
3. Иначе — прежний путь без изменений.
4. FR-205: после каждого удаления (git и копия) печатать в stdout одну строку: `удалено: <путь> | основание: git <ref> | восстановить: safe-delete restore <N>` или `… | основание: копия <путь копии> | восстановить: safe-delete restore <N>`, где N — номер строки записи в ledger.tsv (`wc -l` после записи).
5. Запись в ledger — под `flock` на `$led.lock` (fd, как принято в bash), чтобы N не путался при параллельных вызовах.
6. `restore`: тип `git` → `git -C <repo> cat-file blob <blob> > <путь>` только если пути нет (иначе refuse «существует»); режим 100755 — `chmod +x`.
Тесты (в стиле файла, новые T-номера): T24 git-чистый файл → удалён, `git for-each-ref refs/safe-delete` ≥1, ledger тип git; T25 restore T24 → `cmp` с исходником = 0; T26 изменённый отслеживаемый файл → путь копии; T27 symlink в git → не git-путь; T28 stdout содержит `восстановить: safe-delete restore`.
Проверка (вывод — в отчёт): `bash bin/safe-delete-test` → все PASS; `git diff --stat` — 2 файла.

## U2 — копия 14 дней и запретная зона (атом dcfg-9so4t.2; FR-202, FR-204)
1. Путь через `realpath -e`; если realpath выходит из корней (`:29`) — refuse (уже есть — не дублировать, проверить и добавить только недостающее: symlink, указывающий наружу).
2. Жёсткий отказ всегда (дополнить список сегментов `:37`): `.git .beads .codex hh-scoring secrets`; имена `.env*`, `*.pem`, `*.key`; пути `/etc/claude-code/*`, `$HOME/.ssh/*`, `$HOME/.claude/settings*.json`, сам `$BK` и `$led`, сам файл `safe-delete`.
3. Сегмент `clients` — отказ, КРОМЕ пути с сегментом `.agent-work` внутри clients (`*/clients/*/.agent-work/*`).
4. `restore` записи типа `file`, чья копия удалена `purge` (файла копии нет) → refuse «копия истекла».
Тесты: T29 `.env` → rc 2; T30 symlink наружу корней → rc 2; T31 `clients/x/.agent-work/f` → удалён с копией; T32 `clients/x/f` → rc 2; T33 restore после удаления копии → rc 2 и «копия истекла»; прежний T5b (secrets) — PASS.
Проверка: `bash bin/safe-delete-test` → все PASS.

## U3 — dir и worktree (атом dcfg-9so4t.3; FR-203)
1. `safe-delete dir <каталог>`: сначала проверка ВСЕХ файлов (`find -type f`) правилами `file` (запретная зона → отказ всего, ни один не удаляется); затем каждый файл — путь git или копия (общий код с `file`, без дублирования: вынести тело обработки одного файла в функцию); затем `rmdir` пустых каталогов снизу вверх.
2. `safe-delete worktree <путь>`: путь — worktree (`git -C <путь> rev-parse --git-common-dir` ≠ `.git`); процессы: для каждого `/proc/[0-9]*/cwd`, `readlink` начинается с пути → refuse; нечитаемый cwd чужого процесса — пропуск только если pid не наш пользователь… KISS: при ошибке readlink — refuse; HEAD ветки → `git update-ref refs/safe-delete/wt-<ts> HEAD`; грязные и неотслеживаемые/игнорируемые файлы (`git -C <путь> status --porcelain --ignored`) → копия как в `file`; затем `git worktree remove --force <путь>` (вызов изнутри обёртки); ledger `worktree <путь> <sha> <repo> <ref>`.
3. restore типа `worktree` → `git -C <repo> worktree add <путь> <sha>` и вернуть скопированные файлы (они в ledger отдельными строками `file` — restore по их N).
Тесты: T34 dir с запретным файлом внутри → rc 2, все файлы на месте; T35 dir обычный → удалён, restore файла → cmp; T36 worktree с процессом `sleep` с cwd внутри → rc 2; T37 грязный worktree → снят, ref есть, грязный файл в копии.
Проверка: `bash bin/safe-delete-test` → все PASS; `bash -n bin/safe-delete`.

## U3a — ТЗ v2: ложный отказ на зомби-процессе (атом dcfg-9so4t.3)
Факт: прогон теста 10.10 → `FAIL T36/T37: safe-delete: нечитаемый cwd процесса: 1251326`; `ps -o stat,comm -p 1251326` → `Z<s codex` (зомби). У зомби нет cwd: `readlink /proc/1251326/cwd` → rc 1 (замер на сервере 10.10; источник — вывод команды, не документация).
Правка — только цикл по `/proc/[0-9]*/cwd` в режиме `worktree` файла `bin/safe-delete`: при ошибке `readlink` — пропуск (`continue`), если каталога `/proc/<pid>` уже нет ИЛИ третье поле `/proc/<pid>/stat` равно `Z`; иначе прежний refuse «нечитаемый cwd процесса». Больше ничего не менять; тесты не трогать.
Проверка: `bash bin/safe-delete-test` → PASS T1–T38, 0 FAIL; `bash -n bin/safe-delete`.

## U4 — режим tmp (атом dcfg-9so4t.4, код-часть; FR-207)
Зачем: после managed deny `Bash(rm *)` агенту нужен маршрут удаления во временной зоне без копии.
1. `safe-delete tmp <путь>`: `p=$(realpath -e)`; отказ (refuse, rc 2), если `p` не начинается с `/tmp/` или равен `/tmp`; symlink, указывающий наружу `/tmp`, отсекается этим же realpath. Файл или каталог → `rm -r -- "$p"`, копии нет. Ledger: `log tmp "$p" - - - - deleted` (8 колонок, как соседние). stdout: `удалено: <p> | основание: tmp, без копии`.
2. Добавить `tmp` в строку `usage:` (`--help` и refuse без аргументов). `restore` записи `tmp` — прежний refuse «нельзя восстановить тип» (не трогать).
3. Режим `tmp` не проверяет корни и запретную зону (`check_path` не вызывать) — только условие п.1.
Тесты: T39 файл в `/tmp/<тест>/` → rc 0, файла нет, stdout содержит `основание: tmp`; T40 каталог в `/tmp` → rc 0, каталога нет; T41 путь вне `/tmp` (`/etc/hostname`) → rc 2, файл на месте; T42 symlink в `/tmp` на файл вне `/tmp` (`/etc/hostname`) → rc 2, цель на месте.
Проверка: `bash bin/safe-delete-test` → PASS T1–T42, 0 FAIL; `bash -n bin/safe-delete`.
