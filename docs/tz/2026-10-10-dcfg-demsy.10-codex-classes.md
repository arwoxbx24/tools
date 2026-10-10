# ТЗ dcfg-demsy.10 — классы Codex в disk-rotate

v2 — причина: прогоны 1–2 написали только тесты (сценарии 24–26 уже в рабочем дереве, +53/−2 в `scripts/tests/disk-rotate-gate-selfcheck.sh`), код не успели. Сейчас: тест НЕ трогать; править ТОЛЬКО `scripts/disk-rotate.sh` по пунктам 1–3 ниже, затем прогнать проверку 1–3. Начать сразу с правки кода, без повторной разведки тестов.

## U1 — три узких класса в /root/.codex

Разведка — repowise (индекс tools; нет — `tools/bin/code-memory-enable`). Файлы: `scripts/disk-rotate.sh`, `scripts/tests/disk-rotate-gate-selfcheck.sh`.

Факт 10.10: диск 98% (96G из 99G). `DENY_LIST` (`disk-rotate.sh:68-69`) запрещает весь `/root/.codex/**`, там 13G. Рост ~1.8G в сутки идёт из `/root/.codex/plugins/data/auto-review-just-every/turns`: 3.6G, из них 3.4G старше 12 ч. Старые релизы Codex в `/root/.codex/packages/standalone/releases`: 6 штук по ~430M, активный — цель симлинка `../current`. Сессии `/root/.codex/sessions` старше 14 дней: 1.8G.

Изменение (минимальное, по образцу существующего кода):
1. Новая функция `cleanup_codex`. Вызов — в боевой ветке рядом с `cleanup_always`, на каждом прогоне при открытом гейте (не только soft/hard).
   - **codex-review**: регулярные файлы `turns/**` старше 24 ч (`find -P <turns> -mindepth 2 -type f -mmin +1440 -print0`) удаляются через `handle codex-review` (заменимое). Затем пустые каталоги внутри turns: `find <turns> -mindepth 1 -type d -empty -delete`, только в режиме run.
   - **codex-releases**: каталоги `releases/*`, кроме цели `readlink -f current` и одного самого нового по mtime, оставшегося после неё. Их файлы удаляются через `handle codex-releases` (заменимое). Затем пустые каталоги, только run.
   - **codex-sessions**: файлы `/root/.codex/sessions/**` старше 14 дней (`-mtime +14`) — незаменимое. В run список идёт в `gate_process codex-sessions <list>`: сначала копия restic predelete, удаление по существующему гейту. В dry-run строка через `handle codex-sessions`, как `projects_gate`.
2. `handle` пропускает пути из `DENY_LIST` (`denied`). Для этих трёх баз сделать узкое исключение: переменная-массив `CODEX_ALLOW=(turns releases sessions)` с абсолютными путями. Перед `denied` в `handle` и в `gate_process`, если он фильтрует, путь под одной из баз CODEX_ALLOW не считается запрещённым. Остальной `/root/.codex/**` остаётся под запретом.
3. Базы задать переменными с префиксом по умолчанию (`DR_CODEX_HOME=${DR_CODEX_HOME:-/root/.codex}`), чтобы тест работал во временном каталоге. Боевые пути при этом не меняются.

Тест (`disk-rotate-gate-selfcheck.sh`), по образцу соседних сценариев, только во временном каталоге (`DR_CODEX_HOME=<fixture>`):
- сценарий 24: файл turns старше 24 ч удалён, файл моложе 24 ч цел;
- сценарий 25: из 3 релизов цел `current` и самый новый, третий удалён;
- сценарий 26: сессия старше 14 дней в первом прогоне не удалена, а зафиксирована в restic-заглушке (state или journal `fixed`/`deferred`, как у test-irreplaceable).
Счётчики `22`/`23` в итоговой строке — заменить на актуальное число сценариев.

Принципы: KISS, YAGNI, DRY (переиспользовать `handle`, `gate_process`, `journal_row`), fail fast.
Запреты: `rm -rf` вне /tmp; без сети и живого restic; тесты не трогают боевой `/root/.codex`; без правки crontab и других файлов.

Проверка:
1) `bash -n scripts/disk-rotate.sh` rc 0
2) `bash scripts/tests/disk-rotate-gate-selfcheck.sh` rc 0, все сценарии PASS
3) `scripts/disk-rotate.sh --dry-run | grep -c 'codex-review\|codex-releases\|codex-sessions'` ≥1
