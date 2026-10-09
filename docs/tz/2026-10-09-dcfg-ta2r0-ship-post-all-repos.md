# ТЗ dcfg-ta2r0 v4 — ship-post: доставка из всех репо ga_roots

ТЗ v4 — уточнение владельца 09.10 (spec:099 v4, атом dcfg-8yqv4.11): без настоящей проверки код сам на прод не идёт. Правка v3: `--submit` из репо без workflow `pull_request` в `origin/<основная ветка>:.github/workflows` → rc 0, как в v3. Но скан для такого атома НЕ вызывает `ship`: пишет квитанцию со строкой `wait-owner no-ci`, одну строку `bd note` атома `ship-post: wait-owner no-ci — нет автопроверок, на прод только словом владельца` и больше атом не берёт (квитанция = финал, без повторов). Функция `repo_has_pr_ci <repo>` возвращается (логика v2 п.2). Тест N2 v4: вложенное репо без workflow → `--submit` rc 0; скан: `ship` не вызван, в квитанции `wait-owner no-ci`. Критерий 3 v4: `grep -c 'ga_repo_of' bin/ship-post` ≥ 2; `grep -c 'wait-owner no-ci' bin/ship-post` ≥ 1. Отказ `repository excluded from courier` (N3) остаётся до атома U10 spec:099 v4.

ТЗ v3 — приказ владельца 09.10: «программа работает во всех директориях без исключения». Гейт CI из v2 снят: в репо без CI действуют собственные проверки `ship` — preflight (`bin/ship:48-56`), hooksPath (`:59`), gitleaks (`:86`, `:104`), путь `ci:none` (`:152-153`). Так `ship` уже работает при прямом вызове. Исключения — только `ga_skip_reason` (закон: prod и allowlist), их и так отклоняет `bin/ship:56`. Пункты v2 «repo_has_pr_ci», N2 «без workflow → отказ» и строка скана `no-pr-ci` ОТМЕНЕНЫ. Вместо них: `--submit` из репо без CI → rc 0. Тест N2: вложенное репо без workflow → `--submit` rc 0, скан делает `show` атома. Тест N3: репо с `ga_skip_reason` → `--submit` rc ≠ 0 с `repository excluded from courier`. Критерий 3 v3: `grep -c 'ga_repo_of' bin/ship-post` ≥ 2; `grep -c 'repo_has_pr_ci' bin/ship-post` = 0.

(Ниже — текст v2 для истории; отменённое выше имеет приоритет.)

ТЗ v2 — причина: v1 открывал курьер для репо без CI. `bin/ship:131` отказывает при `ci=none` только в `mode two`, а в `mode one` сливает без проверки. Замер 09.10: в `arwox-v3-src`, `clients/eurosteklo`, `clients/okna-plus` нет workflow с `pull_request` в `origin/main:.github/workflows`.

## U1 — список репо курьера = ga_roots без skip-причин и с CI pull_request
Разведка — repowise; индекс: repowise/CBM проверен (синхронизирован 09.10 до d5ebdfe), нет — `tools/bin/code-memory-enable`.

Причина: `--submit` принимает вложенное репо (`bin/ship-post:110-114`), а `--watch` сканирует только `SHIP_POST_REPOS`, по умолчанию `/root/workspaces/projects:/root/workspaces/tools` (`:46`, цикл `:412`). Атомы вложенных репо закрываются в bd, но их код не доставляется, и это нигде не видно: dcfg-jkd6x, dcfg-wowp4.2, dcfg-3v3z1, dcfg-n575n из `projects/arwox-v3-src`. Вторая ошибка: live sync (`:283-284`) берёт `basename`, а имена `ga_roots` бывают составные (`clients/eurosteklo`).

В worktree уже лежат несданные правки по ТЗ v1 (`git diff HEAD`). Их проверить и довести до v2, лишнее убрать.

Решение (ADR), правка только `bin/ship-post` и `bin/ship-post-test`:
1. В начале `ship-post` подключить `. "$bin/git-auto-lib"`. Сначала убедиться, что подключение не меняет режимы оболочки и имена функций не совпадают (`grep -n '^[a-z_]*()' bin/git-auto-lib bin/ship-post`). При совпадении переименовать функцию в ship-post.
2. Новая функция `repo_has_pr_ci <repo>`, rc 0 или 1. Логика та же, что в `bin/ship:124-130`: есть файл `*.yml`/`*.yaml` в `origin/<основная ветка>:.github/workflows` со строкой `pull_request`. Основная ветка — `git -C <repo> symbolic-ref --short refs/remotes/origin/HEAD` без `origin/`, по умолчанию `main`.
3. `resolve_repos`: если `SHIP_POST_REPOS` задан — поведение прежнее (так работают тесты). Если не задан — каталоги `ga_roots` (3-я колонка), у которых `ga_skip_reason` пуст.
4. `do_submit`: после `repo` (`:107`) взять `name=$(ga_repo_of "$repo")`. Отказ `usage_err` до любого коммита в двух случаях:
   - `ga_skip_reason "$name"` не пуст → `repository excluded from courier: $name ($reason)`;
   - `! repo_has_pr_ci "$repo"` → `repository has no pull_request CI, courier will not merge unchecked code: $name`.
5. `scan_repo`: репо без CI пропускать с одной строкой `skip repo $repo no-pr-ci`, а не по одной на каждый атом.
6. Live sync: `name=$(ga_repo_of "$repo")`, при неудаче — `basename`. Строку `# ponytail: basename …` убрать.
7. `ship`, `git-sync`, `git-auto-lib` не менять.

Тест — `bin/ship-post-test`, функция `test_nested_repo`, номера ≥120:
- N1: вложенное репо `$d/repo/sub` (свой `.git`, workflow с `pull_request` в origin/main, worktree `claude/dcfg-nest.1`), `SHIP_POST_REPOS="$d/repo:$d/repo/sub"` → `--submit` rc 0, скан делает `show dcfg-nest.1`.
- N2: то же, но без workflow → `--submit` rc ≠ 0, в выводе `no pull_request CI`, коммита нет (`rev-list --count` не вырос).
- Существующие проверки не менять и не ослаблять.

Запреты: только `bin/ship-post` и `bin/ship-post-test`; без `--force`, `reset`, `rm -rf`; без новых зависимостей. Принципы: KISS, YAGNI, fail fast.

Критерии:
1. `bash -n bin/ship-post` rc 0.
2. `bin/ship-post-test` → `failures=0`, rc 0, PASS N1 и N2.
3. `grep -c 'repo_has_pr_ci' bin/ship-post` ≥ 3.

Паспорт: `bin/ship:118-134`; `bin/ship-post:7-10,45-48,105-114,275-292,335-420`; `bin/git-auto-lib:20-60,91-98`; `bin/ship-post-test:52-94`.
