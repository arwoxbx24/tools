#!/usr/bin/env bash
# Публикует HTML-файл в MinIO (b244now) без раскрытия ключей агентам.
#
# Агент видит ИМЯ действия, а не ключи. Credentials читает mc из ~/.mc/config.json
# самостоятельно — значения ключей никуда не печатаются и не передаются в аргументах.
#
# Использование: bash tools/secure/publish_page.sh <файл.html> <имя-в-хранилище>
# Пример:        bash tools/secure/publish_page.sh /tmp/report.html report_2026-07-31.html
#
# Возвращает: публичный URL (https://io.b244.ru/files/<имя>) — и только его.
# При ошибке: stderr + exit 1, ключи в сообщениях не упоминаются.
set -euo pipefail

FILE="${1:?Ошибка: укажи файл — tools/secure/publish_page.sh <файл.html> <имя>}"
NAME="${2:?Ошибка: укажи имя в хранилище — tools/secure/publish_page.sh <файл.html> <имя>}"

[[ "$FILE" == *.html ]] || { echo "Ошибка: только .html файлы поддерживаются" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "Ошибка: файл не найден: $FILE" >&2; exit 1; }

# Проверка что mc настроен (алиас b244now существует)
if ! mc alias list b244now >/dev/null 2>&1; then
    echo "Ошибка: алиас b244now не настроен в mc. Настройка: см. docs/SECRETS.md" >&2
    exit 1
fi

# Загрузка: ключи читаются mc из ~/.mc/config.json, значения не передаются в аргументах
if ! mc cp --attr "Content-Type=text/html;Cache-Control=no-store, no-cache, must-revalidate" "$FILE" "b244now/files/$NAME" 2>/tmp/publish_err; then
    # В сообщении об ошибке могут быть credentials — маскируем
    ERR=$(sed 's/access_key=[^&" ]*/access_key=***MASKED***/gi;
               s/secret_key=[^&" ]*/secret_key=***MASKED***/gi;
               s/AccessKeyId=[^&" ]*/AccessKeyId=***MASKED***/gi;
               s/SecretAccessKey=[^&" ]*/SecretAccessKey=***MASKED***/gi' /tmp/publish_err)
    echo "Ошибка загрузки в MinIO: $ERR" >&2
    exit 1
fi

echo "URL: https://io.b244.ru/files/$NAME"
