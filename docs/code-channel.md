# Канал кода

`bin/code-channel` — единственный путь записи кода для Claude и Codex. Голые `opencode run` и `codex exec` запрещены.

## Вызов

- `bin/code-channel auto <проект> <ТЗ-файл>` — автоматическая лестница.
- `bin/code-channel audit <проект> <ТЗ-файл>` — аудит без изменений.
- `bin/code-channel <id> <проект> <ТЗ-файл> [--model <m>]` — явный провайдер.
- Алиасы: `1` = `bitrixgpt`, `2` = `codex`, `3` = `openrouter`.
- `bin/code-channel --plan` показывает включённую лестницу; `bin/code-channel --help` — справку, включая пути к конфигу и этой странице.

## Конфиг и провайдеры

`config/code-channel.json` хранит массив с полями `id`, `enabled`, `model`, `resume_model` (продолжение сессии после rc 124), `audit_model` (модель режима `audit`; пусто — `model`), `effort` (только Codex); `key`, `secret`, `base` — только у платных HTTP-провайдеров. Порядок массива — порядок лестницы.

| id | состояние | модель / параметр |
| --- | --- | --- |
| `go` | включён | code: `opencode-go/glm-5.3-flash`; audit и продолжение: `opencode-go/longcat-2.5-preview-free` |
| `codex` | включён | модель профиля; `effort: high` |
| `openrouter` | выключен | — |
| `bitrixgpt` | выключен | — |
| `kimi` | выключен | подписка Kimi For Coding через `opencode auth login` |

## Переключение и лестница

Измените `enabled` у нужной записи в одной строке и проверьте `bin/code-channel --plan`. Модели и включение платных OpenRouter, Kimi или Bitrix GPT — только по слову владельца.

Ошибка провайдера или rc 0 без изменений переводит к следующему включённому. Сразу остановиться: 3, 5, 15, 22, 24. Последний провайдер возвращает свой rc либо 16.

## Коды выхода

| код | значение |
| --- | --- |
| 3 | неверный вызов, выключенный провайдер или конфиг |
| 5 | см. stderr |
| 11–12, 14 | HTTP-прекверка; см. stderr |
| 13 | денежный стоп `OR_DAILY_STOP` |
| 15 | модель вне белого списка |
| 16 | нет изменений |
| 21 | Codex; см. stderr |
| 22 | audit изменил файлы |
| 23 | сверка провайдера |
| 24 | read-only среда Codex и нет правок (правки есть — rc 0) |
| 30 | рекурсия |
| 124 | таймаут 590 с |

Где значение кода не описано выше, используйте только номер и `см. stderr`.

## Рекурсия и журнал

Внутри исполнителя задан `CODE_CHANNEL_ACTIVE`: любой вызов канала — exit 30. При ошибке не повторяйте канал: прочитайте stderr, исправьте причину, затем один повтор. Исполнитель не делает git add/commit: коммит делает оркестратор (ship-post).

Журнал: `state/code-channel/runs.jsonl` — поля `provider_expected`, `provider_actual`, `rc`.

## Executor file scope

New code TZs can declare exact owned paths before the work description:

```text
Allowed files:
- bin/x
- bin/y
```

Each path is relative to the project Git root. After a code provider runs, `code-channel` rejects a created or changed path outside this list with `out-of-scope: <path>` and a nonzero exit; it does not try another provider after this violation. Existing TZs without the block retain their prior behavior. Include the block in new code TZs so a provider cannot leave unowned worktree files for submission.

## Пролонгация

- Результат прогона неполный — новый файл ТЗ, а не перезапуск того же.
- Имя — `<дата>-<атом>-v2-<суть>.md`, в том же worktree; исходное ТЗ не правится.
- Первая строка нового ТЗ — «Сделано (не трогать): …»: факты прогона N — строка журнала `code-channel: … run=… t=…` и список изменённых файлов; дальше только остаток работы.
- Не больше двух прогонов на атом.
- Второй worktree и второй процесс канала на тот же атом запрещены.

## Чек-лист запуска

- Атом взят: `bd update <атом> --claim`.
- Путь проекта и путь к ТЗ — абсолютные (иначе rc 3 «project must be absolute path»).
- На этом worktree нет живого процесса канала.
- ТЗ: 1–2 файла, ≤100 строк правки, проверка одной командой.
- Вызов один: Bash, `timeout: 600000`; результат по уведомлению.
