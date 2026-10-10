# ТЗ dcfg-5gh8h — safe-delete dir: самодостаточный тестовый стенд с .git

Skills: superpowers:test-driven-development, caveman:surgical-patch, prod.
Закон: `/root/CLAUDE.md` «НЕ ТОРМОЗИТЬ» — ложный отказ на своём артефакте = дефект обёртки; правка только с тестом, что настоящий запрет по-прежнему отказывает.

## U1 Факт
`safe-delete dir /root/workspaces/projects/park_live` → `запрещённый сегмент: .../park_live/repo/.git/FETCH_HEAD`.
Причина: `check_path` (bin/safe-delete, строка ~40) отклоняет любой путь с сегментом `.git`. Каталог — стенд теста ship-post-test: `origin.git` (bare), `repo/` (клон с `remote.origin.url` = `.../park_live/origin.git`), linked worktree внутри. Вне каталога ссылок нет.

## U2 Правка (только `bin/safe-delete` и `bin/safe-delete-test`)
1. В режиме `dir`: перед циклом проверок вычислить «самодостаточный стенд» — функция `self_contained <dir>`, возвращает 0 только если ВСЕ условия:
   - `<dir>` сам не содержит `.git` верхнего уровня как файла/каталога (то есть `<dir>` не корень рабочего репо) — `[[ ! -e $dir/.git ]]`;
   - `<dir>` не отслеживается внешним репо: `git -C "$(dirname "$dir")" ls-files --error-unmatch -- "$(basename "$dir")" >/dev/null 2>&1` возвращает ненулевой код (или родитель не репо);
   - найден хотя бы один вложенный репозиторий (`find "$dir" -name .git -o -name '*.git' -type d -prune` не пуст);
   - для каждого вложенного git-каталога (`*/.git` каталог или bare `*.git`) все `git config --get-regexp '^remote\..*\.url$'` — абсолютные пути, лежащие внутри `<dir>` (`realpath -m` начинается с `$dir/`); любой URL с `:` или `//` (сеть) → не самодостаточный;
   - для `.git`-файлов linked worktree (`gitdir: <path>`) путь `<path>` внутри `<dir>`.
2. Если `self_contained "$dir"` = 0, в `check_path` для путей внутри этого `<dir>` пропустить ТОЛЬКО проверку сегмента `.git` (остальные: корни, `secrets`, `.beads`, `.codex`, `.repowise`, `.env`, ключи, `$BK`, `$self` — без изменений). Реализация: глобальная переменная `allow_git_under=$dir` на время режима `dir`; в цикле сегментов `[[ $seg == .git && -n ${allow_git_under:-} && ( $p == "$allow_git_under" || $p == "$allow_git_under"/* ) ]] && continue`.
3. Удаление файлов — тем же `delete_file`/`check_file`, что сейчас (бэкап/журнал как есть). Если `check_file`/`git_file` мешает для файлов внутри вложенных `.git`, разрешить их тем же условием `allow_git_under`, без других послаблений.
4. Ничего больше не менять.

## U3 Тесты (`bin/safe-delete-test`, сначала красные)
Во временном `SAFE_DELETE_ROOTS` под `/tmp` (как существующие тесты):
- `selfcontained_ok`: каталог `stand/` с `git init --bare stand/origin.git`, `git clone stand/origin.git stand/repo`, коммит, push → `safe-delete dir stand` rc 0, каталога нет.
- `real_repo_refused`: каталог `proj/` — сам git-репо (`git init proj`) → `safe-delete dir proj` отказ с `запрещённый сегмент`.
- `external_remote_refused`: `ext/repo` с `remote.origin.url=https://github.com/x/y.git` → отказ.
- `tracked_refused`: стенд, добавленный в индекс внешнего репо (`git -C outer add stand`) → отказ.
- `beads_still_refused`: самодостаточный стенд, внутри которого есть `.beads/x` → отказ.

## U4 Критерий
`bash -n bin/safe-delete bin/safe-delete-test`; `bash bin/safe-delete-test` — все PASS, failures 0 (до правки кода новые `selfcontained_ok` FAIL, остальные новые PASS).
Живое удаление выполняет главный агент, не исполнитель.
