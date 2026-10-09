# ТЗ dcfg-zlvq3 — ship: правка только *.md в репо без CI → шлюз auto (merge), не wait-owner

## U1 — docs-only в режиме one без CI сливается после gitleaks
Причина (bd dcfg-zlvq3, ADR-25 spec:099; закон «GITHUB БЕЗ ВОПРОСОВ»): `bin/ship:159-165` для `ci == none` всегда отдаёт `prod:wait-owner no-ci`. Для правки только документов видимого результата нет, вопрос владельцу становится техвопросом «отправить на GitHub?» — запрещено.

Решение (ADR-25), правка только `bin/ship`, `bin/ship-test` (или новый `bin/ship-test.d/zlvq3-docs-only.sh`, если тесты так устроены), `docs/ship-post-ARCHITECTURE.md`:
1. В `bin/ship` после цикла определения `ci` (до `if [[ $ci == none && $mode == two ]]`): `docs_only=0`; если `ci == none` и каждый путь `git -C "$wtr" diff --name-only "origin/$base...HEAD"` оканчивается на `.md` (непустой список) → `docs_only=1`. Только `.md`: html/js/скрипты в `docs/**`/`specs/**` — runtime (GitHub Pages), их шлюз прежний.
2. Блок `if [[ $ci == none ]]` (wait-owner) выполнять только при `docs_only == 0`. При `docs_only == 1` печатать `ci:none` и `gate:auto docs-only`, затем обычный путь: проверка `mergeable` (конфликт → 50), БЕЗ `ga_ci_wait` и разбора `ci_rc` (CI нет — ждать нечего), дальше merge, `bd close`, live sync — как в пути с CI.
3. Класс `guarded` (выход до сети) и режим two (отказ `ci-none`) не меняются.

Тест (номер следующий свободный):
- репо plain без workflow, ветка меняет только `README.md` → rc 0, в выводе `gate:auto docs-only`, в журнале stub `gh` есть merge, нет `prod:wait-owner`;
- то же, но ветка меняет `README.md` и `x.sh` → rc 0, `prod:wait-owner no-ci`, merge нет (поведение .12 сохранено).
Прочие проверки не ослаблять.

Дока: в `docs/ship-post-ARCHITECTURE.md` в описании шлюзов добавить строку про docs-only → auto (иначе `ship-doc-check` отклонит PR).

Запреты: только перечисленные файлы и этот ТЗ. Без `--force`, `reset --hard`, `rm -rf` вне `/tmp`. KISS, YAGNI, fail fast.

Критерии:
1. `bash -n bin/ship` → rc 0.
2. `bash bin/ship-test` → `PASS N/N`, rc 0.
3. `bin/ship-doc-check origin/main` → rc 0.
4. `python3 tests/test_agent_tools.py` → OK.
