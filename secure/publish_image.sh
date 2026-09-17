#!/usr/bin/env bash
# устарел (17.09, spec:027) → используй: share <файл>  (/root/workspaces/tools/bin/share)
# Публикует PNG/JPG-файл в MinIO (b244now/hh-qa) без раскрытия ключей агентам.
#
# Использование: bash tools/secure/publish_image.sh <файл.png> <имя-в-хранилище>
# Пример:        bash tools/secure/publish_image.sh /tmp/screen.png qa/dash_mobile.png
#
# Возвращает: публичный URL (https://io.b244.ru/files/<имя>) — и только его.
set -euo pipefail

FILE="${1:?Ошибка: укажи файл — tools/secure/publish_image.sh <файл> <имя>}"
NAME="${2:?Ошибка: укажи имя в хранилище — tools/secure/publish_image.sh <файл> <имя>}"

[[ -f "$FILE" ]] || { echo "Ошибка: файл не найден: $FILE" >&2; exit 1; }

# Определяем content-type по расширению
EXT="${FILE##*.}"
case "${EXT,,}" in
    png)  CTYPE="image/png" ;;
    jpg|jpeg) CTYPE="image/jpeg" ;;
    gif)  CTYPE="image/gif" ;;
    webp) CTYPE="image/webp" ;;
    *)    CTYPE="application/octet-stream" ;;
esac

# Проверка что mc настроен (алиас b244now существует)
if ! mc alias list b244now >/dev/null 2>&1; then
    echo "Ошибка: алиас b244now не настроен в mc" >&2
    exit 1
fi

if ! mc cp --attr "Content-Type=${CTYPE}" "$FILE" "b244now/files/$NAME" 2>/tmp/publish_img_err; then
    ERR=$(sed 's/access_key=[^&" ]*/access_key=***MASKED***/gi;
               s/secret_key=[^&" ]*/secret_key=***MASKED***/gi' /tmp/publish_img_err)
    echo "Ошибка загрузки в MinIO: $ERR" >&2
    exit 1
fi

echo "URL: https://io.b244.ru/files/$NAME"
