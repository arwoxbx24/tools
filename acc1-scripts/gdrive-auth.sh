#!/bin/bash
# gdrive-auth.sh — Google Drive OAuth2 авторизация
# Получение нового refresh token для доступа к Google Drive
# Использование:
#   bash gdrive-auth.sh          — показать URL для авторизации
#   bash gdrive-auth.sh CODE     — обменять код на токен
set -e

CREDENTIALS="/root/workspaces/secrets/services/google/credentials.json"
TOKEN_FILE="/root/workspaces/secrets/services/google/token.json"

# Читаем client_id и client_secret из credentials.json
CLIENT_ID=$(jq -r '.web.client_id' "$CREDENTIALS")
CLIENT_SECRET=$(jq -r '.web.client_secret' "$CREDENTIALS")
REDIRECT_URI="https://b244.ru/oauth/callback"
SCOPE="https://www.googleapis.com/auth/drive.readonly"

if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
    echo "ОШИБКА: Не удалось прочитать client_id из $CREDENTIALS" >&2
    exit 1
fi

if [ -z "$1" ]; then
    # Режим 1: Генерация URL для авторизации
    AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth?client_id=${CLIENT_ID}&redirect_uri=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${REDIRECT_URI}', safe=''))")&response_type=code&scope=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${SCOPE}', safe=''))")&access_type=offline&prompt=consent"

    echo "═══════════════════════════════════════════════════"
    echo "  Google Drive OAuth2 — Авторизация"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Шаг 1: Откройте эту ссылку в браузере:"
    echo ""
    echo "  $AUTH_URL"
    echo ""
    echo "Шаг 2: Войдите в Google-аккаунт и разрешите доступ"
    echo ""
    echo "Шаг 3: Вас перенаправит на b244.ru/oauth/callback?code=XXXX"
    echo "        Скопируйте значение code= из адресной строки"
    echo ""
    echo "Шаг 4: Запустите команду:"
    echo "  bash $0 'ВСТАВЬТЕ_КОД_СЮДА'"
    echo ""
    echo "═══════════════════════════════════════════════════"
    exit 0
fi

# Режим 2: Обмен кода авторизации на токены
AUTH_CODE="$1"

echo "Обмениваем код авторизации на токены..."

TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "code=$AUTH_CODE" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "redirect_uri=$REDIRECT_URI")

# Проверяем ответ
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

if [ -n "$ERROR" ]; then
    ERROR_DESC=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // "неизвестная ошибка"')
    echo "ОШИБКА: $ERROR — $ERROR_DESC" >&2
    echo "Полный ответ: $TOKEN_RESPONSE" >&2
    exit 1
fi

if [ -z "$REFRESH_TOKEN" ]; then
    echo "ОШИБКА: Google не вернул refresh_token" >&2
    echo "Убедитесь что в URL авторизации есть prompt=consent и access_type=offline" >&2
    echo "Полный ответ: $TOKEN_RESPONSE" >&2
    exit 1
fi

# Сохраняем token.json
jq -n \
    --arg type "authorized_user" \
    --arg cid "$CLIENT_ID" \
    --arg cs "$CLIENT_SECRET" \
    --arg rt "$REFRESH_TOKEN" \
    '{type: $type, client_id: $cid, client_secret: $cs, refresh_token: $rt}' \
    > "$TOKEN_FILE"

chmod 600 "$TOKEN_FILE"
echo "✓ Токен сохранён в $TOKEN_FILE"

# Проверяем что токен работает
echo "Проверяем валидность токена..."
VERIFY_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "refresh_token=$REFRESH_TOKEN")

VERIFY_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.access_token // empty')

if [ -n "$VERIFY_TOKEN" ] && [ "$VERIFY_TOKEN" != "null" ]; then
    echo "✓ Токен валиден — Google Drive доступ восстановлен!"

    # Обновляем статус в Redis
    redis-cli SET "system:error:gdrive-token" "ok" EX 604800 >/dev/null 2>&1 || true

    # Записываем статус
    mkdir -p /root/workspaces/tools/acc1-scripts/data
    echo "$(date '+%Y-%m-%d %H:%M:%S') OK — token refreshed successfully" \
        > /root/workspaces/tools/acc1-scripts/data/gdrive-token-status.txt
else
    echo "⚠ Токен сохранён, но верификация не удалась" >&2
    echo "Ответ: $VERIFY_RESPONSE" >&2
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Google Drive OAuth2 — ГОТОВО"
echo "═══════════════════════════════════════════════════"
exit 0
