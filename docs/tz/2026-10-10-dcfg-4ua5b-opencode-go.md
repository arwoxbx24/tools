# ТЗ dcfg-4ua5b v3 — code-channel: форма 3 = OpenCode Go, Bitrix GPT выключен

v3 — причина: v2 (файл-лестница) не уложилась в 590 с исполнителя, лимит Codex 6%. Сначала минимальная правка, чтобы Go заработал; файл-лестница — следующим атомом уже руками Go.

## U1 — три правки в `bin/code-channel`, без разведки, сразу Edit

1. Строка 38 (форма 3): заменить целиком на
   `3) provider=opencode-go; model=opencode-go/mimo-v2.6-flash;;`
2. Строка 113: перед `secrets_root=` вставить строку `if [[ $n == 1 ]]; then`, а после строки 150 (`fi` блока usage_daily, перед `model=${override:-$model}`) вставить `fi`. Так форма 3 не читает секрет и не делает precheck (ключ Go хранит opencode).
3. Строки 155–156 (whitelist): выполнять только для формы 1 — обернуть в `if [[ $n == 1 ]]; then … fi`.
4. Строка 204: `for n in 1 3 2; do` → `for n in 3 2; do`, над ней комментарий `# 10.10 владелец: Bitrix GPT выключен (лимиты); форма 3 = OpenCode Go. Вернуть: for n in 1 3 2`.

`bin/code-channel-test` НЕ трогать (CI поправит следующий атом). Других файлов не трогать.

Источник: https://opencode.ai/docs/go/ — «Model IDs use the format `opencode-go/<model-id>`»; `opencode models opencode-go` содержит `opencode-go/mimo-v2.6-flash` (замер 10.10).

Проверка:
1) `bash -n bin/code-channel` rc 0
2) `grep -c 'opencode-go/mimo-v2.6-flash' bin/code-channel` = 1
3) `grep -c 'for n in 3 2' bin/code-channel` = 1
