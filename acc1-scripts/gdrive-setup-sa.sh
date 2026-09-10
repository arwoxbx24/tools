#!/bin/bash
# gdrive-setup-sa.sh — Одноразовая настройка Service Account для Google Drive
# Использование: bash gdrive-setup-sa.sh /path/to/service-account-key.json
#
# После настройки SA — скачивание из Google Drive полностью автоматическое.
# SA токены генерируются программно через JWT, НИКОГДА не протухают.
set -e

SA_DEST="/root/workspaces/secrets/services/google/service-account.json"

if [ -z "$1" ]; then
    echo "═══════════════════════════════════════════════════"
    echo "  Google Drive Service Account — Настройка"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Service Account обеспечивает ПОЛНОСТЬЮ автоматический"
    echo "доступ к Google Drive без ручной авторизации."
    echo ""
    echo "Как получить ключ Service Account:"
    echo ""
    echo "1. Откройте https://console.cloud.google.com"
    echo "2. Выберите проект (или создайте новый)"
    echo "3. IAM & Admin → Service Accounts → Create Service Account"
    echo "4. Имя: claude-drive-access"
    echo "5. Роль: не нужна (доступ через share)"
    echo "6. После создания → Keys → Add Key → JSON"
    echo "7. Скачается файл .json"
    echo ""
    echo "Затем запустите:"
    echo "  bash $0 /path/to/downloaded-key.json"
    echo ""
    echo "После настройки — расшарьте папку в Google Drive"
    echo "на email Service Account (будет показан после установки)."
    echo ""
    echo "═══════════════════════════════════════════════════"
    exit 0
fi

KEY_FILE="$1"

if [ ! -f "$KEY_FILE" ]; then
    echo "ОШИБКА: Файл не найден: $KEY_FILE" >&2
    exit 1
fi

# Валидация JSON структуры
SA_EMAIL=$(jq -r '.client_email // empty' "$KEY_FILE" 2>/dev/null)
SA_PROJECT=$(jq -r '.project_id // empty' "$KEY_FILE" 2>/dev/null)
SA_TYPE=$(jq -r '.type // empty' "$KEY_FILE" 2>/dev/null)
SA_KEY_ID=$(jq -r '.private_key_id // empty' "$KEY_FILE" 2>/dev/null)

if [ "$SA_TYPE" != "service_account" ]; then
    echo "ОШИБКА: Это не файл Service Account (type=$SA_TYPE)" >&2
    exit 1
fi

if [ -z "$SA_EMAIL" ] || [ -z "$SA_PROJECT" ]; then
    echo "ОШИБКА: Неполный файл ключа (нет client_email или project_id)" >&2
    exit 1
fi

# Копируем ключ
cp "$KEY_FILE" "$SA_DEST"
chmod 600 "$SA_DEST"

echo "═══════════════════════════════════════════════════"
echo "  Service Account настроен!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  Email:   $SA_EMAIL"
echo "  Project: $SA_PROJECT"
echo "  Key ID:  $SA_KEY_ID"
echo "  Путь:    $SA_DEST"
echo ""
echo "  ВАЖНО: Расшарьте нужные папки в Google Drive"
echo "  на этот email: $SA_EMAIL"
echo ""
echo "  После этого — скачивание полностью автоматическое."
echo "═══════════════════════════════════════════════════"

# Обновляем статус
mkdir -p /root/workspaces/tools/acc1-scripts/data
echo "$(date '+%Y-%m-%d %H:%M:%S') SA_CONFIGURED — $SA_EMAIL" \
    > /root/workspaces/tools/acc1-scripts/data/gdrive-token-status.txt
redis-cli DEL "system:error:gdrive-token" >/dev/null 2>&1 || true

exit 0
